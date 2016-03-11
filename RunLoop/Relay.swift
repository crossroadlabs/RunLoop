//===--- Relay.swift ----------------------------------------------===//
//Copyright (c) 2016 Daniel Leping (dileping)
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//http://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
//===----------------------------------------------------------------------===//

import Foundation
import Boilerplate

public extension RunLoopType {
    public func urgent(task:SafeTask) {
        if let relayable = self as? RelayRunLoopType {
            relayable.urgent(true, task: task)
        } else {
            self.execute(task)
        }
    }
    
    //anyways must be reimplemented in non-relayable runloop
    func execute(task: SafeTask) {
        guard let relayable = self as? RelayRunLoopType else {
            CommonRuntimeError.NotImplemented(what: "You need to implement 'execute(task: SafeTask)' function").panic()
        }
        relayable.execute(true, task: task)
    }
    
    //anyways must be reimplemented in non-relayable runloop
    func execute(delay:Timeout, task: SafeTask) {
        guard let relayable = self as? RelayRunLoopType else {
            CommonRuntimeError.NotImplemented(what: "You need to implement 'execute(delay:Timeout, task: SafeTask)' function").panic()
        }
        relayable.execute(true, delay: delay, task: task)
    }
    
    func urgentNoRelay(task:SafeTask) {
        guard let relayable = self as? RelayRunLoopType else {
            self.urgent(task)
            return
        }
        relayable.urgent(false, task: task)
    }
    
    func executeNoRelay(task:SafeTask) {
        guard let relayable = self as? RelayRunLoopType else {
            self.execute(task)
            return
        }
        relayable.execute(false, task: task)
    }
    
    func executeNoRelay(delay:Timeout, task:SafeTask) {
        guard let relayable = self as? RelayRunLoopType else {
            self.execute(delay, task: task)
            return
        }
        relayable.execute(false, delay: delay, task: task)
    }
}

public protocol RelayRunLoopType : RunLoopType {
    var relay:RunLoopType? {get set}
    
    func urgent(relay:Bool, task:SafeTask)
    func execute(relay:Bool, task: SafeTask)
    func execute(relay:Bool, delay:Timeout, task: SafeTask)
}

public extension RelayRunLoopType {
    func urgent(relay:Bool, task:SafeTask) {
        self.execute(relay, task: task)
    }
}