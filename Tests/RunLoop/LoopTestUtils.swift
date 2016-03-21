//
//  LoopTestUtils.swift
//  RunLoop
//
//  Created by Yegor Popovych on 3/21/16.
//  Copyright © 2016 Crossroad Labs, LTD. All rights reserved.
//

import Foundation
import Boilerplate

@testable import RunLoop

func threadWithRunLoop<RL: RunLoopType>() -> (thread:Thread, loop: RL) {
    var sema: SemaphoreType
    sema = BlockingSemaphore()
    var loop: RL?
    let thread = try! Thread {
        loop = RL.current as? RL
        sema.signal()
        (loop as? RunnableRunLoopType)?.run()
    }
    sema.wait()
    return (thread, loop!)
}

