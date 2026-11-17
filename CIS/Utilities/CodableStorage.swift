//
//  Storage.swift
//  CIS
//
//  Created by samsam on 11/16/26.
//

import class Foundation.UserDefaults
import struct Foundation.URL

@propertyWrapper
internal struct Storage<Value> {
    internal typealias Callback = (Value) -> Void

    internal let key: String
    internal let defaultValue: Value
    internal let callback: Callback?

    internal init(key: String, defaultValue: Value, callback: Callback? = nil) {
		self.key = key
		self.defaultValue = defaultValue
		self.callback = callback
	}
	
    internal var wrappedValue: Value {
		get {
			return UserDefaults.standard.object(forKey: key) as? Value ?? defaultValue
		}
		set {
			UserDefaults.standard.set(newValue, forKey: key)
			callback?(newValue)
		}
	}
}

@propertyWrapper
internal struct EnumStorage<Value: RawRepresentable> {
    internal typealias Callback = (Value) -> Void

    internal let key: String
    internal let defaultValue: Value
    internal let callback: Callback?

    internal init(key: String, defaultValue: Value, callback: Callback? = nil) {
        self.key = key
        self.defaultValue = defaultValue
        self.callback = callback
    }

    internal var wrappedValue: Value {
        get {
            guard let rawValue = UserDefaults.standard.object(forKey: key) as? Value.RawValue else {
                return defaultValue
            }
            return Value(rawValue: rawValue) ?? defaultValue
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            callback?(newValue)
        }
    }
}
