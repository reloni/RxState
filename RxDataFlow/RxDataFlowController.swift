//
//  RxDataFlowController.swift
//  RxState
//
//  Created by Anton Efimenko on 02.11.16.
//  Copyright © 2016 Anton Efimenko. All rights reserved.
//

import Foundation
import RxSwift

public protocol RxDataFlowControllerType {
	func dispatch(_ action: RxActionType)
}

public protocol RxStateType { }

public protocol RxReducerType {
	func handle(_ action: RxActionType, flowController: RxDataFlowControllerType) -> Observable<RxStateType>
}

public protocol RxActionType {
	var scheduler: ImmediateSchedulerType? { get }
}

public struct RxCompositeAction : RxActionType {
	public let scheduler: ImmediateSchedulerType?
	public let actions: [RxActionType]
	public init(actions: [RxActionType], scheduler: ImmediateSchedulerType? = nil) {
		self.actions = actions
		self.scheduler = scheduler
	}
}

public struct RxInitializationAction : RxActionType {
	public var scheduler: ImmediateSchedulerType?
}


public final class RxDataFlowController<State: RxStateType> : RxDataFlowControllerType {
	public var state: Observable<(setBy: RxActionType, state: State)> { return currentStateSubject.asObservable().observeOn(scheduler) }
	public var currentState: (setBy: RxActionType, state: State) { return stateStack.peek()! }
	public var errors: Observable<(state: State, action: RxActionType, error: Error)> { return errorsSubject }
	
	let bag = DisposeBag()
	let reducer: RxReducerType
	let scheduler: ImmediateSchedulerType
	
	var stateStack: FixedStack<(setBy: RxActionType, state: State)>
	var actionsQueue = Queue<RxActionType>()
	var isActionExecuting = BehaviorSubject(value: false)
	
	let currentStateSubject: BehaviorSubject<(setBy: RxActionType, state: State)>
	let errorsSubject = PublishSubject<(state: State, action: RxActionType, error: Error)>()
	
	public convenience init(reducer: RxReducerType,
	                        initialState: State,
	                        maxHistoryItems: UInt = 50,
	                        dispatchAction: RxActionType? = nil) {
		self.init(reducer: reducer,
		          initialState: initialState,
		          maxHistoryItems: maxHistoryItems,
		          scheduler: SerialDispatchQueueScheduler(qos: .utility, internalSerialQueueName: "RxStore.DispatchQueue"),
		          dispatchAction: dispatchAction)
	}
	
	init(reducer: RxReducerType,
	     initialState: State,
	     maxHistoryItems: UInt = 50,
	     scheduler: ImmediateSchedulerType,
	     dispatchAction: RxActionType? = nil) {
		self.scheduler = scheduler
		self.reducer = reducer
		stateStack = FixedStack(capacity: maxHistoryItems)
		stateStack.push((setBy: RxInitializationAction(), state: initialState))
		
		currentStateSubject = BehaviorSubject(value: (setBy: RxInitializationAction(), state: initialState))
		
		subscribe()
		
		if let dispatchAction = dispatchAction {
			dispatch(dispatchAction)
		}
	}
	
	private func subscribe() {
		currentStateSubject.skip(1).subscribe(onNext: { [weak self] newState in self?.stateStack.push(newState) }).addDisposableTo(bag)
		
		actionsQueue.currentItemSubject.observeOn(scheduler)
			.flatMap { [weak self] action -> Observable<Void> in
				guard let object = self else { return Observable.empty() }
				
				return object.observe(action: action)
			}.subscribe().addDisposableTo(bag)
	}
	
	private func observe(action: RxActionType) -> Observable<Void> {
		let object = self
		let handle: Observable<(setBy: RxActionType, state: RxStateType)> = {
			guard let compositeAction = action as? RxCompositeAction else {
				return Observable<RxActionType>.from([action], scheduler: action.scheduler ?? object.scheduler)
					.flatMap { act in object.reducer.handle(act, flowController: object).subscribeOn(act.scheduler ?? object.scheduler) }
					.flatMap { result -> Observable<(setBy: RxActionType, state: RxStateType)> in return .just((setBy: action, state: result)) }
			}
			return object.observe(compositeAction: compositeAction)
		}()
		
		return handle
			.do(onNext: { object.currentStateSubject.onNext((setBy: $0.setBy, state: $0.state as! State)) },
			    onError: { object.errorsSubject.onNext((state: object.currentState.state, action: action, error: $0)) },
			    onDispose: { _ in _ = object.actionsQueue.dequeue() })
			.flatMap { result -> Observable<RxStateType?> in .just(result.state) }
			.catchErrorJustReturn(nil)
			.flatMap { _ in return Observable<Void>.just() }
	}
	
	func observe(compositeAction: RxCompositeAction) -> Observable<(setBy: RxActionType, state: RxStateType)> {
		return Observable.create { [weak self] observer in
			guard let object = self else { return Disposables.create() }
			
			var compositeQueue = Queue<RxActionType>()
			
			let disposable = compositeQueue.currentItemSubject.observeOn(object.scheduler).flatMap { action -> Observable<RxStateType> in
				return Observable.create { _ in
					let subscribsion = Observable.from([action], scheduler: action.scheduler ?? compositeAction.scheduler ?? object.scheduler)
						.flatMap { act -> Observable<RxStateType> in
							object.reducer.handle(act, flowController: object).subscribeOn(act.scheduler ?? compositeAction.scheduler ?? object.scheduler)
						}
						.do(onNext: { observer.onNext((setBy: action, state: $0)) },
						    onError: { observer.onError($0) },
						    onCompleted: { _ = compositeQueue.dequeue() },
						    onDispose: { if compositeQueue.count == 0 { observer.onCompleted() } })
						.subscribe()
					return Disposables.create { subscribsion.dispose() }
				}
				}.subscribe()
			
			for a in compositeAction.actions { compositeQueue.enqueue(a) }
			
			return Disposables.create { disposable.dispose() }
		}
	}
	
	public func dispatch(_ action: RxActionType) {
		scheduler.schedule((action, self)) { params in
			return Observable<Void>.create { observer in
				params.1.actionsQueue.enqueue(params.0)
				return Disposables.create()
				}.subscribe()
			}.addDisposableTo(bag)
	}
}
