// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

abstract contract CallbackUtil {
    error NotExpectingCallbackFrom(address expected, address actual);
    error NotExpectingCallback(address sender);

    address private expectingCaller;

    modifier checkCallbackFrom() {
        address expectCallFrom = expectingCaller;

        if (expectCallFrom == address(0)) {
            revert NotExpectingCallback(msg.sender);
        }
        if (expectCallFrom != msg.sender) {
            revert NotExpectingCallbackFrom(expectCallFrom, msg.sender);
        }

        _;
    }

    function _expectCallbackFrom(address _caller) internal {
        expectingCaller = _caller;
    }

    function _invalidateCallback() internal {
        expectingCaller = address(0);
    }
}
