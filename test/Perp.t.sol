// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import {Test} from "forge-std/Test.sol";

import {IPerp, Perp} from "src/Perp.sol";
import {Access} from "src/access/Access.sol";
import {Errors} from "src/lib/Errors.sol";

contract PerpTest is Test {
    address private exchange = makeAddr("exchange");
    address private clearingService = makeAddr("clearingService");
    address private orderBook = makeAddr("orderBook");

    Access private access;
    Perp private perpEngine;

    function setUp() public {
        access = new Access();
        access.initialize(address(this));
        access.setExchange(exchange);
        access.setClearingService(clearingService);
        access.setOrderBook(orderBook);

        perpEngine = new Perp();
        perpEngine.initialize(address(access));
    }

    function test_initialize() public view {
        assertEq(address(perpEngine.access()), address(access));
    }

    function test_initialize_revertsIfSetZeroAddr() public {
        Perp _perp = new Perp();
        vm.expectRevert(Errors.ZeroAddress.selector);
        _perp.initialize(address(0));
    }

    function test_authorized() public {
        vm.prank(exchange);
        perpEngine.updateFundingRate(0, 0);

        vm.prank(clearingService);
        perpEngine.updateFundingRate(0, 0);

        vm.prank(orderBook);
        perpEngine.updateFundingRate(0, 0);
    }

    function test_updateFundingRate() public {
        vm.startPrank(exchange);

        uint8 productId = 0;
        int128[4] memory rates = [int128(-10), 20, -15, 30];
        int128 cumulativeFunding = 0;

        for (uint256 i = 0; i < rates.length; i++) {
            perpEngine.updateFundingRate(productId, rates[i]);
            cumulativeFunding += rates[i];
            assertEq(perpEngine.getFundingRate(productId).cumulativeFunding18D, cumulativeFunding);
        }
    }

    function test_updateFundingRate_revertsWhenUnauthorized() public {
        vm.expectRevert(Errors.Unauthorized.selector);
        perpEngine.updateFundingRate(0, 0);
    }

    function test_modifyAccount() public {
        vm.startPrank(exchange);

        IPerp.AccountDelta[] memory deltas = new IPerp.AccountDelta[](2);
        deltas[0] = IPerp.AccountDelta({productIndex: 0, account: makeAddr("account0"), amount: 100, quoteAmount: 100});
        deltas[1] = IPerp.AccountDelta({productIndex: 1, account: makeAddr("account1"), amount: 200, quoteAmount: -100});
        for (uint256 i = 0; i < deltas.length; i++) {
            perpEngine.modifyAccount(deltas);
            IPerp.Balance memory balance = perpEngine.getBalance(deltas[i].account, deltas[i].productIndex);
            assertEq(balance.size, deltas[i].amount);
            assertEq(balance.quoteBalance, deltas[i].quoteAmount);
        }
    }

    function test_modifyAccount_revertsWhenUnauthorized() public {
        IPerp.AccountDelta[] memory deltas = new IPerp.AccountDelta[](0);
        vm.expectRevert(Errors.Unauthorized.selector);
        perpEngine.modifyAccount(deltas);
    }
}
