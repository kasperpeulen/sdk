// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of html;

/**
 * Adapter for exposing DOM events as Dart streams.
 */
class _EventStream<T extends Event> extends Stream<T> {
  final EventTarget _target;
  final String _eventType;
  final bool _useCapture;

  _EventStream(this._target, this._eventType, this._useCapture);

  // DOM events are inherently multi-subscribers.
  Stream<T> asBroadcastStream({void onListen(StreamSubscription subscription),
                               void onCancel(StreamSubscription subscription)})
      => this;
  bool get isBroadcast => true;

  StreamSubscription<T> listen(void onData(T event),
      { void onError(error),
        void onDone(),
        bool cancelOnError}) {

    return new _EventStreamSubscription<T>(
        this._target, this._eventType, onData, this._useCapture);
  }
}

/** A specialized Stream available to [Element]s to enable event delegation. */
abstract class ElementStream<T extends Event> implements Stream<T> {
  /**
   * Return a stream that only fires when the particular event fires for
   * elements matching the specified CSS selector.
   *
   * This is the Dart equivalent to jQuery's
   * [delegate](http://api.jquery.com/delegate/).
   */
  Stream<T> matches(String selector);
}

/**
 * Adapter for exposing DOM Element events as streams, while also allowing
 * event delegation.
 */
class _ElementEventStreamImpl<T extends Event> extends _EventStream<T>
    implements ElementStream<T> {
  _ElementEventStreamImpl(target, eventType, useCapture) :
      super(target, eventType, useCapture);

  Stream<T> matches(String selector) =>
      this.where((event) => event.target.matchesWithAncestors(selector));
}

/**
 * Adapter for exposing events on a collection of DOM Elements as streams,
 * while also allowing event delegation.
 */
class _ElementListEventStreamImpl<T extends Event> extends Stream<T>
    implements ElementStream<T> {
  final _StreamPool _pool;
  Stream<T> _stream;

  _ElementListEventStreamImpl(targetList, eventType, useCapture) :
      _pool = new _StreamPool.broadcast() {
    for (Element target in targetList) {
      var stream = new _EventStream(target, eventType, useCapture);
      _pool.add(stream);
    }
    _stream = _pool.stream;
  }

  Stream<T> matches(String selector) =>
      this.where((event) => event.target.matchesWithAncestors(selector));

  // Delegate all regular Stream behavor to our wrapped Stream.
  StreamSubscription<T> listen(void onData(T event),
      { void onError(error),
        void onDone(),
        bool cancelOnError}) =>
      _stream.listen(onData, onError: onError, onDone: onDone,
          cancelOnError: cancelOnError);
  Stream<T> asBroadcastStream({void onListen(StreamSubscription subscription),
                               void onCancel(StreamSubscription subscription)})
      => _stream;
  bool get isBroadcast => true;
}

/**
 * A pool of streams whose events are unified and emitted through a central
 * stream.
 */
// TODO (efortuna): Remove this when Issue 12218 is addressed.
class _StreamPool<T> {
  StreamController<T> _controller;

  /// Subscriptions to the streams that make up the pool.
  var _subscriptions = new Map<Stream<T>, StreamSubscription<T>>();

  /**
   * Creates a new stream pool where [stream] can be listened to more than
   * once.
   *
   * Any events from buffered streams in the pool will be emitted immediately,
   * regardless of whether [stream] has any subscribers.
   */
  _StreamPool.broadcast() {
    _controller = new StreamController<T>.broadcast(sync: true,
        onCancel: close);
  }

  /**
   * The stream through which all events from streams in the pool are emitted.
   */
  Stream<T> get stream => _controller.stream;

  /**
   * Adds [stream] as a member of this pool.
   *
   * Any events from [stream] will be emitted through [this.stream]. If
   * [stream] is sync, they'll be emitted synchronously; if [stream] is async,
   * they'll be emitted asynchronously.
   */
  void add(Stream<T> stream) {
    if (_subscriptions.containsKey(stream)) return;
    _subscriptions[stream] = stream.listen(_controller.add,
        onError: _controller.addError,
        onDone: () => remove(stream));
  }

  /** Removes [stream] as a member of this pool. */
  void remove(Stream<T> stream) {
    var subscription = _subscriptions.remove(stream);
    if (subscription != null) subscription.cancel();
  }

  /** Removes all streams from this pool and closes [stream]. */
  void close() {
    for (var subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _controller.close();
  }
}

class _EventStreamSubscription<T extends Event> extends StreamSubscription<T> {
  int _pauseCount = 0;
  EventTarget _target;
  final String _eventType;
  var _onData;
  final bool _useCapture;

  _EventStreamSubscription(this._target, this._eventType, this._onData,
      this._useCapture) {
    _tryResume();
  }

  void cancel() {
    if (_canceled) return;

    _unlisten();
    // Clear out the target to indicate this is complete.
    _target = null;
    _onData = null;
  }

  bool get _canceled => _target == null;

  void onData(void handleData(T event)) {
    if (_canceled) {
      throw new StateError("Subscription has been canceled.");
    }
    // Remove current event listener.
    _unlisten();

    _onData = handleData;
    _tryResume();
  }

  /// Has no effect.
  void onError(void handleError(error)) {}

  /// Has no effect.
  void onDone(void handleDone()) {}

  void pause([Future resumeSignal]) {
    if (_canceled) return;
    ++_pauseCount;
    _unlisten();

    if (resumeSignal != null) {
      resumeSignal.whenComplete(resume);
    }
  }

  bool get isPaused => _pauseCount > 0;

  void resume() {
    if (_canceled || !isPaused) return;
    --_pauseCount;
    _tryResume();
  }

  void _tryResume() {
    if (_onData != null && !isPaused) {
      _target.$dom_addEventListener(_eventType, _onData, _useCapture);
    }
  }

  void _unlisten() {
    if (_onData != null) {
      _target.$dom_removeEventListener(_eventType, _onData, _useCapture);
    }
  }

  Future asFuture([var futureValue]) {
    // We just need a future that will never succeed or fail.
    Completer completer = new Completer();
    return completer.future;
  }
}

/**
 * A factory to expose DOM events as Streams.
 */
class EventStreamProvider<T extends Event> {
  final String _eventType;

  const EventStreamProvider(this._eventType);

  /**
   * Gets a [Stream] for this event type, on the specified target.
   *
   * This will always return a broadcast stream so multiple listeners can be
   * used simultaneously.
   *
   * This may be used to capture DOM events:
   *
   *     Element.keyDownEvent.forTarget(element, useCapture: true).listen(...);
   *
   * Or for listening to an event which will bubble through the DOM tree:
   *
   *     MediaElement.pauseEvent.forTarget(document.body).listen(...);
   *
   * See also:
   *
   * [addEventListener](http://docs.webplatform.org/wiki/dom/methods/addEventListener)
   */
  Stream<T> forTarget(EventTarget e, {bool useCapture: false}) =>
    new _EventStream(e, _eventType, useCapture);

  /**
   * Gets an [ElementEventStream] for this event type, on the specified element.
   *
   * This will always return a broadcast stream so multiple listeners can be
   * used simultaneously.
   *
   * This may be used to capture DOM events:
   *
   *     Element.keyDownEvent.forElement(element, useCapture: true).listen(...);
   *
   * See also:
   *
   * [addEventListener](http://docs.webplatform.org/wiki/dom/methods/addEventListener)
   */
  ElementStream<T> forElement(Element e, {bool useCapture: false}) {
    return new _ElementEventStreamImpl(e, _eventType, useCapture);
  }

  /**
   * Gets an [ElementEventStream] for this event type, on the list of elements.
   *
   * This will always return a broadcast stream so multiple listeners can be
   * used simultaneously.
   *
   * This may be used to capture DOM events:
   *
   *     Element.keyDownEvent._forElementList(element, useCapture: true).listen(...);
   *
   * See also:
   *
   * [addEventListener](http://docs.webplatform.org/wiki/dom/methods/addEventListener)
   */
  ElementStream<T> _forElementList(ElementList e, {bool useCapture: false}) {
    return new _ElementListEventStreamImpl(e, _eventType, useCapture);
  }

  /**
   * Gets the type of the event which this would listen for on the specified
   * event target.
   *
   * The target is necessary because some browsers may use different event names
   * for the same purpose and the target allows differentiating browser support.
   */
  String getEventType(EventTarget target) {
    return _eventType;
  }
}

/**
 * A factory to expose DOM events as streams, where the DOM event name has to
 * be determined on the fly (for example, mouse wheel events).
 */
class _CustomEventStreamProvider<T extends Event>
    implements EventStreamProvider<T> {

  final _eventTypeGetter;
  const _CustomEventStreamProvider(this._eventTypeGetter);

  Stream<T> forTarget(EventTarget e, {bool useCapture: false}) {
    return new _EventStream(e, _eventTypeGetter(e), useCapture);
  }

  ElementStream<T> forElement(Element e, {bool useCapture: false}) {
    return new _ElementEventStreamImpl(e, _eventTypeGetter(e), useCapture);
  }

  ElementStream<T> _forElementList(ElementList e,
      {bool useCapture: false}) {
    return new _ElementListEventStreamImpl(e, _eventTypeGetter(e), useCapture);
  }

  String getEventType(EventTarget target) {
    return _eventTypeGetter(target);
  }
}