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

public extension RunLoopProtocol {
    public func urgent(task:SafeTask) {
        if let relayable = self as? RelayRunLoopProtocol {
            relayable.urgent(relay: true, task: task)
        } else {
            self.execute(task: task)
        }
    }
    
    //anyways must be reimplemented in non-relayable runloop
    public func execute(task: SafeTask) {
        guard let relayable = self as? RelayRunLoopProtocol else {
            CommonRuntimeError.NotImplemented(what: "You need to implement 'execute(task: SafeTask)' function").panic()
        }
        relayable.execute(relay: true, task: task)
    }
    
    //anyways must be reimplemented in non-relayable runloop
    public func execute(delay:Timeout, task: SafeTask) {
        guard let relayable = self as? RelayRunLoopProtocol else {
            CommonRuntimeError.NotImplemented(what: "You need to implement 'execute(delay:Timeout, task: SafeTask)' function").panic()
        }
        relayable.execute(relay: true, delay: delay, task: task)
    }
    
    public func urgentNoRelay(task:SafeTask) {
        guard let relayable = self as? RelayRunLoopProtocol else {
            self.urgent(task: task)
            return
        }
        relayable.urgent(relay: false, task: task)
    }
    
    public func executeNoRelay(task:SafeTask) {
        guard let relayable = self as? RelayRunLoopProtocol else {
            self.execute(task: task)
            return
        }
        relayable.execute(relay: false, task: task)
    }
    
    func executeNoRelay(delay:Timeout, task:SafeTask) {
        guard let relayable = self as? RelayRunLoopProtocol else {
            self.execute(delay: delay, task: task)
            return
        }
        relayable.execute(relay: false, delay: delay, task: task)
    }
}

public protocol RelayRunLoopProtocol : RunLoopProtocol {
    var relay:RunLoopProtocol? {get set}
    
    func urgent(relay:Bool, task:SafeTask)
    func execute(relay:Bool, task: SafeTask)
    func execute(relay:Bool, delay:Timeout, task: SafeTask)
}

public extension RelayRunLoopProtocol {
    func urgent(relay:Bool, task:SafeTask) {
        self.execute(relay: relay, task: task)
    }
}
