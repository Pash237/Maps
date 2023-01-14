//
//  File.swift
//  
//
//  Created by Pavel Alexeev on 03.01.2023.
//

import UIKit

final class TapGestureRecognizer: UITapGestureRecognizer {
	private var action: (TapGestureRecognizer) -> Void

	init(action: @escaping (TapGestureRecognizer) -> Void) {
		self.action = action
		super.init(target: nil, action: nil)
		self.cancelsTouchesInView = false
		self.delaysTouchesBegan = false
		self.delaysTouchesEnded = false
		self.addTarget(self, action: #selector(targetAction))
	}

	@objc private func targetAction() {
		action(self)
	}
}


final class LongPressGestureRecognizer: UILongPressGestureRecognizer {
	private let feedbackGenerator = UINotificationFeedbackGenerator()
	private var action: (LongPressGestureRecognizer) -> Void

	init(action: @escaping (LongPressGestureRecognizer) -> Void) {
		self.action = action
		super.init(target: nil, action: nil)
		self.cancelsTouchesInView = false
		self.delaysTouchesBegan = false
		self.delaysTouchesEnded = false
	}

	
	public override var state: UIGestureRecognizer.State {
		didSet {
			if state == .began {
				action(self)
				feedbackGenerator.notificationOccurred(.success)
			}
		}
	}
	
	public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
		feedbackGenerator.prepare()
		super.touchesBegan(touches, with: event)
	}
}
