//
//  RxDataFlow.swift
//  RxStateTests
//
//  Created by Anton Efimenko on 02.11.16.
//  Copyright © 2016 Anton Efimenko. All rights reserved.
//

import XCTest
import RxSwift
@testable import RxDataFlow

class RxDataFlowTests: XCTestCase {
    let timeout: TimeInterval = 10
    
	func testObjectPassedToControllerDeinited() {
		let store: TestFlowController! = TestFlowController(reducer: testStoreReducer,
															initialState: TestState(text: "Initial value"))
		
		let deinitExpectation = expectation(description: "Object should be deinited")
		
		store.dispatch(ChangeTextValueAction(newText: "New text 1"))
		store.dispatch(EnumAction.deinitObject(DeinitObject({ deinitExpectation.fulfill() })))
		store.dispatch(ChangeTextValueAction(newText: "New text 2"))
		store.dispatch(ChangeTextValueAction(newText: "New text 2"))
		store.dispatch(ChangeTextValueAction(newText: "New text 2"))
		store.dispatch(ChangeTextValueAction(newText: "New text 2"))
		store.dispatch(ChangeTextValueAction(newText: "New text 2"))
		
		let deinitResult = XCTWaiter().wait(for: [deinitExpectation], timeout: timeout)
		XCTAssertEqual(deinitResult, .completed)
	}
	
	func testObjectPassedToControllerStoredAndNotDeinited() {
		let store: TestFlowController! = TestFlowController(reducer: testStoreReducer,
															initialState: TestState(text: "Initial value"))
		
		let deinitExpectation = expectation(description: "Object should be deinited")
		store.dispatch(ChangeTextValueAction(newText: "New text 1"))
		store.dispatch(EnumAction.deinitObject(DeinitObject({ deinitExpectation.fulfill() })))
		
		let deinitResult = XCTWaiter().wait(for: [deinitExpectation], timeout: timeout)
		XCTAssertEqual(deinitResult, .timedOut)
		XCTAssertEqual(store.currentState.state.text, "Deinit object")
	}
	
	/// Test FlowController deinit if there is no actions to dispatch
	func testDeinit() {
		var store: TestFlowController! = TestFlowController(reducer: testStoreReducer,
		                               initialState: TestState(text: "Initial value"))
		
		let deinitExpectation = expectation(description: "Should deinit")
		
		store.onDeinit = { _ in
			deinitExpectation.fulfill()
		}
		
		let completeExpectation = expectation(description: "Should not fulfill this expectation")
		
		var stateHistory = [String]()
		_ = store.state
            .do(onNext: { stateHistory.append($0.state.text) })
            .filter { $0.setBy is CompletionAction }
            .do(onNext: { _ in completeExpectation.fulfill() })
            .subscribe()
		
		let delayScheduler = SerialDispatchQueueScheduler(qos: .utility)
		
		let action1 = CustomObservableAction(scheduler: nil, observable: Observable.just(TestState(text: "Action executed (1)")).delay(.milliseconds(100), scheduler: delayScheduler), isSerial: true)
		let action2 = CustomObservableAction(scheduler: nil, observable: Observable.just(TestState(text: "Action executed (2)")).delay(.milliseconds(300), scheduler: delayScheduler), isSerial: true)
		let action3 = CustomObservableAction(scheduler: nil, observable: Observable.just(TestState(text: "Action executed (3)")).delay(.milliseconds(700), scheduler: delayScheduler), isSerial: true)
		let action4 = CustomObservableAction(scheduler: nil, observable: Observable.just(TestState(text: "Action executed (4)")).delay(.milliseconds(1000), scheduler: delayScheduler), isSerial: true)
		
		store.dispatch(action1)
		store.dispatch(action2)
		store.dispatch(action3)
		store.dispatch(action4)
		store.dispatch(CompletionAction())
		
		let completeResult = XCTWaiter().wait(for: [completeExpectation], timeout: timeout)
		
		store = nil
		
		let deinitResult = XCTWaiter().wait(for: [deinitExpectation], timeout: timeout)
		
		
		XCTAssertEqual(deinitResult, .completed)
		XCTAssertEqual(completeResult, .completed)
		XCTAssertNotNil(stateHistory)
		XCTAssertEqual(6, stateHistory.count)
	}
	
	/// Test FlowController stop action execution on deinit
	func testDeinit_2() {
		var store: TestFlowController! = TestFlowController(reducer: testStoreReducer,
		                                                    initialState: TestState(text: "Initial value"))
		
		let deinitExpectation = expectation(description: "Should deinit")
		
		store.onDeinit = { _ in
			deinitExpectation.fulfill()
		}
		
		let completeExpectation = expectation(description: "Should not fulfill this expectation")
		
		var stateHistory = [String]()
		_ = store.state
            .do(onNext: { stateHistory.append($0.state.text) })
            .filter { $0.setBy is CompletionAction }
            .do(onNext: { _ in completeExpectation.fulfill() })
            .subscribe()
		
		let delayScheduler = SerialDispatchQueueScheduler(qos: .utility)
		
		for i in 0..<1000 {
			let action = CustomObservableAction(scheduler: nil, observable: Observable.just(TestState(text: "Action executed \(i)")).delay(.milliseconds(1), scheduler: delayScheduler), isSerial: true)
			store.dispatch(action)
		}
		
		store.dispatch(CompletionAction())
		
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			store = nil
		}
		
		let completeResult = XCTWaiter().wait(for: [completeExpectation], timeout: timeout)
		let deinitResult = XCTWaiter().wait(for: [deinitExpectation], timeout: timeout)
		
		
		XCTAssertEqual(deinitResult, .completed)
		XCTAssertEqual(completeResult, .timedOut)
		XCTAssertNotNil(stateHistory)
		XCTAssertTrue(stateHistory.count < 1000)
	}
	
	func testInitialState() {
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"))
		XCTAssertEqual(store.currentState.state.text, "Initial value")
		XCTAssertNotNil(store.currentState.setBy as? RxInitializationAction)
	}
	
	func testReturnCurrentStateOnSubscribe() {
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"))
		let completeExpectation = expectation(description: "Should return initial state")
		
		_ = store.state.subscribe(onNext: { next in
			guard next.setBy is RxInitializationAction else { return }
			guard next.state.text == "Initial value" else { return }
			completeExpectation.fulfill()
		})
		
		let result = XCTWaiter().wait(for: [completeExpectation], timeout: timeout)
		XCTAssertEqual(result, .completed)
	}
	
	func testDispatchActionAfterInitialization() {
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"),
		                                 dispatchAction: ChangeTextValueAction(newText: "Change on init"))
		
		let completeExpectation = expectation(description: "Should dispatch action after initialization")
		
		_ = store.state.subscribe(onNext: { next in
			guard next.setBy is ChangeTextValueAction else { return }
			completeExpectation.fulfill()
		})
		
		let result = XCTWaiter().wait(for: [completeExpectation], timeout: timeout)
		
		XCTAssertEqual(result, .completed)
	}
	
	func testPerformAction() {
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"))
		let completeExpectation = expectation(description: "Should change state")
		
		_ = store.state.subscribe(onNext: { next in
			guard next.setBy is ChangeTextValueAction else { return }
			XCTAssertEqual(next.state.text, "New text")
			completeExpectation.fulfill()
		})
		
		store.dispatch(ChangeTextValueAction(newText: "New text"))
		
		let result = XCTWaiter().wait(for: [completeExpectation], timeout: timeout)
		
		XCTAssertEqual(result, .completed)
	}
	
	func testPorformActionAndPropagateError() {
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"))
		let errorExpectation = expectation(description: "Should rise error")
		
		_ = store.errors.subscribe(onNext: { e in
			XCTAssertEqual(TestError.someError, e.error as! TestError)
			XCTAssertTrue(e.action is ErrorAction)
			XCTAssertEqual("New text before error", e.state.text)
			if case TestError.someError = e.error {
				errorExpectation.fulfill()
			}
		})
		store.dispatch(ChangeTextValueAction(newText: "New text 1"))
		store.dispatch(ChangeTextValueAction(newText: "New text 2"))
		store.dispatch(ChangeTextValueAction(newText: "New text before error"))
		store.dispatch(ErrorAction())
		
		let result = XCTWaiter().wait(for: [errorExpectation], timeout: timeout)
		XCTAssertEqual(result, .completed)
	}
    
    func testPorformActionAndPropagateError_2() {
        let stateObservable: Observable<TestState> = Observable.create {
            $0.onNext(TestState(text: ""))
            $0.onCompleted()
            return Disposables.create()
        }
        
        let error = stateObservable.map { e -> TestState in
            throw TestError.someError
        }
        
        let store = RxDataFlowController(reducer: testStoreReducer,
                                         initialState: TestState(text: "Initial value"))
        let errorExpectation = expectation(description: "Should rise error")

        _ = store.errors.subscribe(onNext: { e in
            XCTAssertEqual(TestError.someError, e.error as! TestError)
            XCTAssertTrue(e.action is CustomObservableAction)
            XCTAssertEqual("New text before error", e.state.text)
            if case TestError.someError = e.error {
                errorExpectation.fulfill()
            }
        })
        store.dispatch(ChangeTextValueAction(newText: "New text 1"))
        store.dispatch(ChangeTextValueAction(newText: "New text 2"))
        store.dispatch(ChangeTextValueAction(newText: "New text before error"))
        store.dispatch(CustomObservableAction(scheduler: nil, observable: error, isSerial: true))
        

        let result = XCTWaiter().wait(for: [errorExpectation], timeout: timeout)
        XCTAssertEqual(result, .completed)
    }
	
	func testContinueWorkAfterErrorAction() {
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"))
		let completeExpectation = expectation(description: "Should perform all non-error actions")
		
		var changeTextValueActionCount = 0
		_ = store.state.filter { $0.setBy is ChangeTextValueAction }.subscribe(onNext: { next in
			changeTextValueActionCount += 1
		})
		
		var stateHistory = [String]()
		_ = store.state
            .do(onNext: { stateHistory.append($0.state.text) })
            .filter { $0.setBy is CompletionAction }
            .do(onNext: { _ in completeExpectation.fulfill() })
            .subscribe()
		
		store.dispatch(ChangeTextValueAction(newText: "New text 1"))
		store.dispatch(ChangeTextValueAction(newText: "New text 2"))
		store.dispatch(ChangeTextValueAction(newText: "New text 3"))
		store.dispatch(ErrorAction())
		store.dispatch(ChangeTextValueAction(newText: "New text 4"))
		store.dispatch(ChangeTextValueAction(newText: "Last text change"))
		store.dispatch(CompletionAction())
		
		let result = XCTWaiter().wait(for: [completeExpectation], timeout: timeout)
		
		XCTAssertEqual(result, .completed)
		XCTAssertEqual(5, changeTextValueActionCount, "Should change text five times")
		XCTAssertEqual("Completed", store.currentState.state.text)
		let expectedStateHistoryTextValues = ["Initial value",
		                                      "New text 1",
		                                      "New text 2",
		                                      "New text 3",
		                                      "New text 4",
		                                      "Last text change",
		                                      "Completed"]
		
		XCTAssertEqual(expectedStateHistoryTextValues, stateHistory)
	}
	
	
	func testSerialActionDispatch_1() {
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"))
		let completeExpectation = expectation(description: "Should perform all non-error actions")
		
		var stateHistory = [String]()
		_ = store.state
            .do(onNext: { stateHistory.append($0.state.text) })
            .filter { $0.setBy is CompletionAction }
            .do(onNext: { _ in completeExpectation.fulfill() })
            .subscribe()
		
		let delayScheduler = SerialDispatchQueueScheduler(qos: .utility)
		
		for i in 1...11 {
            let after: RxTimeInterval = (i % 2 == 0) ? .milliseconds(150) : .milliseconds(0)
			let action: RxActionType = {
				if i == 11 {
					return CompletionAction()
				} else if i % 3 == 0 {
					let descriptor = Observable<TestState>.error(TestError.someError).delaySubscription(after, scheduler: delayScheduler)
					return CustomObservableAction(scheduler: delayScheduler, observable: descriptor, isSerial: true)
				} else {
					let descriptor = Observable<TestState>.just(TestState(text: "Action \(i) executed")).delaySubscription(after, scheduler: delayScheduler)
					return CustomObservableAction(scheduler: delayScheduler, observable: descriptor, isSerial: true)
				}
			}()
			
			store.dispatch(action)
		}
		
		let result = XCTWaiter().wait(for: [completeExpectation], timeout: 5)
		XCTAssertEqual(result, .completed)
		
		let expectedStateHistoryTextValues = ["Initial value",
		                                      "Action 1 executed",
		                                      "Action 2 executed",
		                                      "Action 4 executed",
		                                      "Action 5 executed",
		                                      "Action 7 executed",
		                                      "Action 8 executed",
		                                      "Action 10 executed",
		                                      "Completed"]
		
		XCTAssertEqual(expectedStateHistoryTextValues, stateHistory)
	}
	
	func testSerialActionDispatch_2() {
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"))
		let completeExpectation = expectation(description: "Should perform all non-error actions")
		
		var stateHistory = [String]()
		_ = store.state
            .do(onNext: { stateHistory.append($0.state.text) })
            .filter { $0.setBy is CompletionAction }
            .do(onNext: { _ in completeExpectation.fulfill() })
            .subscribe()
		
		let descriptor1: Observable<TestState> = {
			return Observable.create { observer in
				XCTAssertEqual(store.currentState.state.text, "Action 1 executed")
				DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + 1.0) {
					XCTAssertEqual(store.currentState.state.text, "Action 1 executed")
					observer.onNext(TestState(text: "Action 2 executed"))
					observer.onCompleted()
				}
				return Disposables.create()
			}
		}()
		let descriptor2: Observable<TestState> = {
			return Observable.create { observer in
				XCTAssertEqual(store.currentState.state.text, "Action 2 executed")
				DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + 0.4) {
					XCTAssertEqual(store.currentState.state.text, "Action 2 executed")
					observer.onNext(TestState(text: "Action 3 executed"))
					observer.onCompleted()
				}
				return Disposables.create()
			}
		}()
		
		store.dispatch(ChangeTextValueAction(newText: "Action 1 executed"))
		store.dispatch(CustomObservableAction(scheduler: nil, observable: descriptor1, isSerial: true))
		store.dispatch(CustomObservableAction(scheduler: nil, observable: descriptor2, isSerial: true))
		store.dispatch(ChangeTextValueAction(newText: "Action 4 executed"))
		store.dispatch(CompletionAction())
		
		let result = XCTWaiter().wait(for: [completeExpectation], timeout: 5)
		XCTAssertEqual(result, .completed)
		
		let expectedStateHistoryTextValues = ["Initial value",
		                                      "Action 1 executed",
		                                      "Action 2 executed",
		                                      "Action 3 executed",
		                                      "Action 4 executed",
		                                      "Completed"]
		
		XCTAssertEqual(expectedStateHistoryTextValues, stateHistory)
	}
	
	func testDispatch_1() {
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"))
		let completeExpectation = expectation(description: "Should perform all non-error actions")
		
		var stateHistory = [String]()
		_ = store.state
            .do(onNext: { stateHistory.append($0.state.text) })
            .filter { $0.setBy is CompletionAction }
            .do(onNext: { _ in completeExpectation.fulfill() })
            .subscribe()
		
		store.dispatch(ChangeTextValueAction(newText: "New text 1"))
		DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + 0.01) { store.dispatch(ChangeTextValueAction(newText: "New text 2")) }
		DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + 0.1) { store.dispatch(ChangeTextValueAction(newText: "New text 3")) }
		DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + 0.30) { store.dispatch(CompletionAction()) }
		
		let result = XCTWaiter().wait(for: [completeExpectation], timeout: timeout)
		XCTAssertEqual(result, .completed)
		
		XCTAssertEqual("Completed", store.currentState.state.text)
		let expectedStateHistoryTextValues = ["Initial value",
		                                      "New text 1",
		                                      "New text 2",
		                                      "New text 3",
		                                      "Completed"]
		
		XCTAssertEqual(expectedStateHistoryTextValues, stateHistory)
	}
	
	func testDispatchInCorrectScheduler_1() {
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"))
		let completeExpectation = expectation(description: "Should perform all non-error actions")
		
		var stateHistory = [String]()
		_ = store.state
            .do(onNext: { stateHistory.append($0.state.text) })
            .filter { $0.setBy is CompletionAction }
            .do(onNext: { _ in completeExpectation.fulfill() })
            .subscribe()
		
		let action1Scheduler = TestScheduler(internalScheduler: SerialDispatchQueueScheduler(qos: .utility))
		
		let descriptor: Observable<TestState> = {
			return Observable.create { observer in
				XCTAssertTrue(!Thread.isMainThread)
				observer.onNext(TestState(text: "Action 1 executed"))
				observer.onCompleted()
				return Disposables.create()
			}
		}()
		let action1 = CustomObservableAction(scheduler: action1Scheduler, observable: descriptor, isSerial: true)
		store.dispatch(action1)
		store.dispatch(CompletionAction())
		
		let result = XCTWaiter().wait(for: [completeExpectation], timeout: timeout)
		XCTAssertEqual(result, .completed)
		
		let expectedStateHistoryTextValues = ["Initial value",
		                                      "Action 1 executed",
		                                      "Completed"]
		
		XCTAssertEqual(1, action1Scheduler.scheduleCounter)
		XCTAssertEqual(expectedStateHistoryTextValues, stateHistory)
	}
	
	func testDispatchInCorrectScheduler_2() {
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"))
		let completeExpectation = expectation(description: "Should perform all non-error actions")
		
		var stateHistory = [String]()
		_ = store.state
            .do(onNext: { stateHistory.append($0.state.text) })
            .filter { $0.setBy is CompletionAction }
            .do(onNext: { _ in completeExpectation.fulfill() })
            .subscribe()
		
		let actionScheduler = TestScheduler(internalScheduler: SerialDispatchQueueScheduler(qos: .utility))
		
		let action1 = CustomObservableAction(scheduler: actionScheduler, observable: .just(TestState(text: "Action 1 executed")), isSerial: true)
		let action2 = CustomObservableAction(scheduler: actionScheduler, observable: .just(TestState(text: "Action 2 executed")), isSerial: true)
		let action3 = CustomObservableAction(scheduler: actionScheduler, observable: .just(TestState(text: "Action 3 executed")), isSerial: true)
		
		store.dispatch(action1)
		store.dispatch(action2)
		store.dispatch(action3)
		store.dispatch(CompletionAction())
		
		let result = XCTWaiter().wait(for: [completeExpectation], timeout: timeout)
		XCTAssertEqual(result, .completed)
		
		let expectedStateHistoryTextValues = ["Initial value",
		                                      "Action 1 executed",
		                                      "Action 2 executed",
		                                      "Action 3 executed",
		                                      "Completed"]
		
		XCTAssertEqual(3, actionScheduler.scheduleCounter)
		XCTAssertEqual(expectedStateHistoryTextValues, stateHistory)
	}
	
	func testDispatchInDefaultScheduler() {
		let storeScheduler = TestScheduler(internalScheduler: SerialDispatchQueueScheduler(qos: .utility))
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"),
		                                 scheduler: storeScheduler)
		let completeExpectation = expectation(description: "Should perform all non-error actions")
		
		var stateHistory = [String]()
		_ = store.state
            .do(onNext: { stateHistory.append($0.state.text) })
            .filter { $0.setBy is CompletionAction }
            .do(onNext: { _ in completeExpectation.fulfill() })
            .subscribe()
		
		let action1 = CustomObservableAction(scheduler: nil, observable: .just(TestState(text: "Action 1 executed")), isSerial: true)
		let action2 = CustomObservableAction(scheduler: nil, observable: .just(TestState(text: "Action 2 executed")), isSerial: true)
		
		let action3Scheduler = TestScheduler(internalScheduler: SerialDispatchQueueScheduler(qos: .utility))
		let action3 = CustomObservableAction(scheduler: action3Scheduler, observable: .just(TestState(text: "Action 3 executed")), isSerial: true)
		
		store.dispatch(action1)
		store.dispatch(action2)
		store.dispatch(action3)
		store.dispatch(CompletionAction())
		
		let result = XCTWaiter().wait(for: [completeExpectation], timeout: timeout)
		XCTAssertEqual(result, .completed)
		
		let expectedStateHistoryTextValues = ["Initial value",
		                                      "Action 1 executed",
		                                      "Action 2 executed",
		                                      "Action 3 executed",
		                                      "Completed"]
		
		XCTAssertEqual(3, storeScheduler.scheduleCounter)
		XCTAssertEqual(1, action3Scheduler.scheduleCounter)
		XCTAssertEqual(expectedStateHistoryTextValues, stateHistory)
	}
	
	func testDispatchInMainScheduer() {
		let storeScheduler = TestScheduler(internalScheduler: SerialDispatchQueueScheduler(qos: .utility))
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"),
		                                 scheduler: storeScheduler)
		let completeExpectation = expectation(description: "Should perform all non-error actions")
		
		var stateHistory = [String]()
        _ = store.state
            .do(onNext: { stateHistory.append($0.state.text) })
            .filter { $0.setBy is CompletionAction }
            .do(onNext: { _ in completeExpectation.fulfill() })
            .subscribe()
		
		let descriptor: Observable<TestState> = {
			return Observable.create { observer in
				XCTAssertTrue(Thread.isMainThread)
				observer.onNext(TestState(text: "Action 1 executed"))
				observer.onCompleted()
				return Disposables.create()
			}
		}()
		let action1 = CustomObservableAction(scheduler: MainScheduler.instance, observable: descriptor, isSerial: true)
		
		store.dispatch(action1)
		store.dispatch(CompletionAction())
		
		let result = XCTWaiter().wait(for: [completeExpectation], timeout: timeout)
		XCTAssertEqual(result, .completed)
		
		let expectedStateHistoryTextValues = ["Initial value",
		                                      "Action 1 executed",
		                                      "Completed"]
		
		XCTAssertEqual(1, storeScheduler.scheduleCounter)
		XCTAssertEqual(expectedStateHistoryTextValues, stateHistory)
	}
	
	func testMultipleStateChangesInOneDescriptor() {
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"))
		let completeExpectation = expectation(description: "Should perform all non-error actions")
		
		var stateHistory = [String]()
		_ = store.state
            .do(onNext: { stateHistory.append($0.state.text) })
            .filter { $0.setBy is CompletionAction }
            .do(onNext: { _ in completeExpectation.fulfill() })
            .subscribe()
		
		let descriptor: Observable<TestState> = {
			return Observable.create { observer in
				observer.onNext(TestState(text: "Action executed (1)"))
				observer.onNext(TestState(text: "Action executed (2)"))
				
				DispatchQueue.global(qos: .background).asyncAfter(deadline: DispatchTime.now() + 1.5) {
					observer.onNext(TestState(text: "Action executed (3)"))
					observer.onNext(TestState(text: "Action executed (4)"))
					observer.onCompleted()
				}
				
				return Disposables.create()
			}
		}()
		let action1 = CustomObservableAction(scheduler: nil, observable: descriptor, isSerial: true)
		
		store.dispatch(action1)
		store.dispatch(CompletionAction())
		
		let result = XCTWaiter().wait(for: [completeExpectation], timeout: timeout)
		XCTAssertEqual(result, .completed)
		
		let expectedStateHistoryTextValues = ["Initial value",
		                                      "Action executed (1)",
		                                      "Action executed (2)",
		                                      "Action executed (3)",
		                                      "Action executed (4)",
		                                      "Completed"]
		
		XCTAssertEqual(expectedStateHistoryTextValues, stateHistory)
	}
	
	func testDispatchReducerHandleFunctionInCorrectScheduler() {
		let store = RxDataFlowController(reducer: testStoreReducer,
		                                 initialState: TestState(text: "Initial value"))
		let completeExpectation = expectation(description: "Should perform all non-error actions")
		
		var stateHistory = [String]()
		_ = store.state
            .do(onNext: { stateHistory.append($0.state.text) })
            .filter { $0.setBy is CompletionAction }
            .do(onNext: { _ in completeExpectation.fulfill() })
            .subscribe()
		
		let action1Descriptor: Observable<TestState> = {
			return Observable.create { observer in
				XCTAssertTrue(Thread.isMainThread)
				observer.onNext(TestState(text: "Action 1 executed"))
				observer.onCompleted()
				return Disposables.create()
			}
		}()
		
		let action1 = EnumAction.inMainScheduler(action1Descriptor)
		
		let action2Scheduler = TestScheduler(internalScheduler: SerialDispatchQueueScheduler(qos: .utility))
		let action2 = EnumAction.inCustomScheduler(action2Scheduler, .just(TestState(text: "Action 2 executed")))
		
		store.dispatch(action1)
		store.dispatch(action2)
		store.dispatch(CompletionAction())
		
		let result = XCTWaiter().wait(for: [completeExpectation], timeout: timeout)
		XCTAssertEqual(result, .completed)
		
		let expectedStateHistoryTextValues = ["Initial value",
		                                      "Action 1 executed",
		                                      "Action 2 executed",
		                                      "Completed"]
		
		XCTAssertEqual(1, action2Scheduler.scheduleCounter)
		XCTAssertEqual(expectedStateHistoryTextValues, stateHistory)
	}
    
    func testStoreAndPassCorrectState() {
        let store = RxDataFlowController(reducer: testStoreReducer,
                                         initialState: TestState(text: "Initial value"))
        let completeExpectation = expectation(description: "Should perform all non-error actions")
        
        _ = store.state.filter { $0.setBy is CompletionAction }.subscribe(onNext: { next in
            completeExpectation.fulfill()
        })

        store.dispatch(CompareStateAction(isSerial: true, scheduler: nil, newText: "Value 1", stateText: "Initial value"))
        store.dispatch(CompareStateAction(isSerial: true, scheduler: nil, newText: "Value 2", stateText: "Value 1"))
        store.dispatch(CompareStateAction(isSerial: true, scheduler: nil, newText: "Value 3", stateText: "Value 2"))
        store.dispatch(CompareStateAction(isSerial: true, scheduler: nil, newText: "Value 4", stateText: "Value 3"))
        store.dispatch(CompletionAction())
        
        let result = XCTWaiter().wait(for: [completeExpectation], timeout: 100)
        XCTAssertEqual(result, .completed)
        
        XCTAssertEqual("Completed", store.currentState.state.text)
    }
}
