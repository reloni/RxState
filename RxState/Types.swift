//
//  Types.swift
//  RxState
//
//  Created by Anton Efimenko on 06.11.16.
//  Copyright © 2016 Anton Efimenko. All rights reserved.
//

import Foundation
import RxSwift

public protocol RxStateType { }

public protocol RxReducerType {
	func handle(_ action: RxActionType, actionResult: RxActionResultType, currentState: RxStateType) -> Observable<RxStateType>
}

public final class RxActionWork {
	public let workScheduler: ImmediateSchedulerType?
	public let scheduledWork: (RxStateType) -> Observable<RxActionResultType>
	
	public init(scheduler: ImmediateSchedulerType? = nil, scheduledWork: @escaping (RxStateType) -> Observable<RxActionResultType>) {
		self.workScheduler = scheduler
		self.scheduledWork = scheduledWork
	}
	
	internal func schedule(in outerScheduler: ImmediateSchedulerType, state: RxStateType) -> Observable<RxActionResultType> {
		guard let workScheduler = workScheduler else {
			return scheduledWork(state).subscribeOn(outerScheduler)
		}
		return scheduledWork(state).subscribeOn(workScheduler)
	}
}

public protocol RxActionType {
	var work: RxActionWork { get }
}

public protocol RxActionResultType { }


public struct RxDefaultAction : RxActionType {
	public var work: RxActionWork
}

public struct RxInitialStateAction : RxActionType {
	public var work: RxActionWork {
		return RxActionWork { _ in Observable.empty() }
	}
}

public struct RxDefaultActionResult<T> : RxActionResultType {
	public let value: T
	public init(_ value: T) {
		self.value = value
	}
}
