// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {Access} from "./access/Access.sol";
import {IClearingService} from "./interfaces/IClearingService.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IPerp} from "./interfaces/IPerp.sol";
import {ISpot} from "./interfaces/ISpot.sol";
import {Errors} from "./lib/Errors.sol";
import {LibOrder} from "./lib/LibOrder.sol";
import {MathHelper} from "./lib/MathHelper.sol";
import {Percentage} from "./lib/Percentage.sol";
import {MAX_LIQUIDATION_FEE_RATE, MAX_MATCH_FEES, MAX_TAKER_SEQUENCER_FEE} from "./share/Constants.sol";
import {OrderSide} from "./share/Enums.sol";

/// @title Orderbook contract
/// @notice This contract is used for matching orders
/// @dev This contract is upgradeable
contract OrderBook is IOrderBook, Initializable, OwnableUpgradeable {
    using MathHelper for int128;
    using Percentage for uint128;

    IClearingService public clearingService;
    ISpot public spotEngine;
    IPerp public perpEngine;
    Access public access;

    ///@notice manage the fullfiled amount of an order
    mapping(bytes32 orderHash => uint128 filledAmount) public filled;
    mapping(address account => mapping(uint64 nonce => bool used)) public isNonceUsed;

    FeeCollection public feeCollection; // 手续费汇总
    address private collateralToken; // 抵押token
    int256 private totalSequencerFee; // 排序器的手续费

    function initialize(
        address _clearingService,
        address _spotEngine,
        address _perpEngine,
        address _access,
        address _collateralToken
    ) public initializer {
        if (
            _clearingService == address(0) || _spotEngine == address(0) || _perpEngine == address(0)
                || _access == address(0) || _collateralToken == address(0)
        ) {
            revert Errors.ZeroAddress();
        }
        clearingService = IClearingService(_clearingService);
        spotEngine = ISpot(_spotEngine);
        perpEngine = IPerp(_perpEngine);
        access = Access(_access);
        collateralToken = _collateralToken;
    }

    function _onlySequencer() internal view {
        if (msg.sender != access.getExchange()) {
            revert Errors.Unauthorized();
        }
    }

    modifier onlySequencer() {
        _onlySequencer();
        _;
    }

    /// @inheritdoc IOrderBook
    // solhint-disable code-complexity
    function matchOrders( //只提交匹配成功的订单。即链上与链下状态应该要保持一致！！！。队列是在链下完成。
        LibOrder.SignedOrder calldata maker,
        LibOrder.SignedOrder calldata taker,
        OrderHash calldata digest,
        uint8 productIndex,
        uint128 takerSequencerFee,
        Fee calldata matchFee
    ) external onlySequencer {
        if (maker.order.orderSide == taker.order.orderSide) {
            revert Errors.Orderbook_OrdersWithSameSides();
        }
        if (maker.order.sender == taker.order.sender) {
            revert Errors.Orderbook_OrdersWithSameAccounts();
        }
        if (takerSequencerFee > MAX_TAKER_SEQUENCER_FEE) {
            revert Errors.Orderbook_ExceededMaxSequencerFee();
        }

        // 填充数量（合约份数）
        uint128 fillAmount =
            MathHelper.min(maker.order.size - filled[digest.maker], taker.order.size - filled[digest.taker]);
        _verifyUsedNonce(maker.order.sender, maker.order.nonce);
        _verifyUsedNonce(taker.order.sender, taker.order.nonce);

        _validatePrice(maker.order.orderSide, maker.order.price, taker.order.price);
        uint128 price = maker.order.price;

        Delta memory takerDelta;
        Delta memory makerDelta;
        // 根据吃单者的方向，做不同的策略。
        if (taker.order.orderSide == OrderSide.SELL) {
            takerDelta.productAmount = -int128(fillAmount);
            makerDelta.productAmount = int128(fillAmount);
            takerDelta.quoteAmount = int128(price).mul18D(int128(fillAmount));
            makerDelta.quoteAmount = -takerDelta.quoteAmount;
        } else {
            takerDelta.productAmount = int128(fillAmount);
            makerDelta.productAmount = -int128(fillAmount);
            makerDelta.quoteAmount = int128(price).mul18D(int128(fillAmount));
            takerDelta.quoteAmount = -makerDelta.quoteAmount;
        }
        if (
            matchFee.maker > MathHelper.abs(makerDelta.quoteAmount.mul18D(MAX_MATCH_FEES))
                || matchFee.taker > MathHelper.abs(takerDelta.quoteAmount.mul18D(MAX_MATCH_FEES))
        ) {
            revert Errors.Orderbook_ExceededMaxTradingFee();
        }

        if (taker.isLiquidation) {
            // 清算
            uint128 liquidationFee = matchFee.liquidationPenalty;
            uint128 maxLiquidationFee =
                uint128(MathHelper.abs(takerDelta.quoteAmount)).calculatePercentage(MAX_LIQUIDATION_FEE_RATE);

            if (liquidationFee > maxLiquidationFee) {
                revert Errors.Orderbook_ExceededMaxLiquidationFee();
            }

            takerDelta.quoteAmount -= int128(liquidationFee);
            clearingService.collectLiquidationFee(taker.order.sender, taker.order.nonce, liquidationFee);
        }

        // 报价
        makerDelta.quoteAmount = makerDelta.quoteAmount - matchFee.maker;
        takerDelta.quoteAmount = takerDelta.quoteAmount - matchFee.taker;
        _updateFeeCollection(matchFee);

        //sequencer fee application
        if (filled[digest.taker] == 0) {
            totalSequencerFee += int128(takerSequencerFee);
            takerDelta.quoteAmount -= int128(takerSequencerFee);
        }

        filled[digest.maker] += fillAmount;
        filled[digest.taker] += fillAmount;
        if (maker.order.size == filled[digest.maker]) {
            isNonceUsed[maker.order.sender][maker.order.nonce] = true;
        }
        if (taker.order.size == filled[digest.taker]) {
            isNonceUsed[taker.order.sender][taker.order.nonce] = true;
        }
        // settle maker
        (makerDelta.quoteAmount, makerDelta.productAmount) =
            _settleBalance(productIndex, maker.order.sender, makerDelta.productAmount, makerDelta.quoteAmount, price);

        //handle taker position settle
        (takerDelta.quoteAmount, takerDelta.productAmount) =
            _settleBalance(productIndex, taker.order.sender, takerDelta.productAmount, takerDelta.quoteAmount, price);

        {
            IPerp.AccountDelta[] memory productDeltas = new IPerp.AccountDelta[](2);

            // 0: maker info
            // 1: taker info
            productDeltas[0] =
                _createAccountDelta(productIndex, maker.order.sender, makerDelta.productAmount, makerDelta.quoteAmount);
            productDeltas[1] =
                _createAccountDelta(productIndex, taker.order.sender, takerDelta.productAmount, takerDelta.quoteAmount);

            // 仓位调整
            _modifyAccounts(productDeltas);
        }
        bool isLiquidation = taker.isLiquidation;
        emit OrderMatched(
            productIndex,
            maker.order.sender,
            taker.order.sender,
            maker.order.orderSide,
            maker.order.nonce,
            taker.order.nonce,
            fillAmount,
            price,
            matchFee,
            isLiquidation
        );
    }

    /// @inheritdoc IOrderBook
    function claimTradingFees() external onlySequencer returns (int256) {
        int256 totalFees = feeCollection.perpFeeCollection;
        feeCollection.perpFeeCollection = 0;
        return totalFees;
    }

    /// @inheritdoc IOrderBook
    function claimSequencerFees() external onlySequencer returns (int256) {
        int256 totalFees = totalSequencerFee;
        totalSequencerFee = 0;
        return totalFees;
    }

    /// @inheritdoc IOrderBook
    function getCollateralToken() external view returns (address) {
        return collateralToken;
    }

    /// @inheritdoc IOrderBook
    function getTradingFees() external view returns (int128) {
        return feeCollection.perpFeeCollection;
    }

    /// @inheritdoc IOrderBook
    function getSequencerFees() external view returns (int256) {
        return totalSequencerFee;
    }

    /// @inheritdoc IOrderBook
    function isMatched(address _userA, uint64 _nonceA, address _userB, uint64 _nonceB) external view returns (bool) {
        return isNonceUsed[_userA][_nonceA] || isNonceUsed[_userB][_nonceB];
    }

    /// @dev This internal function is used to call modify account function depends on the quote address.
    /// If the quote address is QUOTE_ADDRESS, it will call perpEngine.modifyAccount.
    /// Otherwise, it will call spotEngine.modifyAccount.
    /// @param _accountDeltas The information of the account to modify
    function _modifyAccounts(IPerp.AccountDelta[] memory _accountDeltas) internal {
        perpEngine.modifyAccount(_accountDeltas);
    }

    function _updateFeeCollection(Fee calldata fee) internal {
        feeCollection.perpFeeCollection += fee.maker + fee.taker - int128(fee.referralRebate);
    }

    function _settleBalance( //结算
        uint8 _productIndex,
        address _account,
        int128 _matchSize,
        int128 _quote,
        uint128 _price
    ) internal returns (int128, int128) {
        ISpot.AccountDelta[] memory accountDeltas = new ISpot.AccountDelta[](1);
        IPerp.Balance memory balance = perpEngine.getBalance(_account, _productIndex);
        IPerp.FundingRate memory fundingRate = perpEngine.getFundingRate(_productIndex);

        //pay funding first 计算资金费率，资金费率 - 当前的持仓对应的价格累计
        // funding：资金费用 = 资金费率 * 仓位价值 = 资金费率 * 标价价格 * 合约数量 = （资金费率 * 标价价格） * 合约数量
        //（资金费率 * 标价价格）： 单份合约（资金费率）价差累计偏离值。
        // 例如：资金费率是8小时调整一次，已经经过5次调整。分别是8、-2、-3、6、3，
        int128 funding = (fundingRate.cumulativeFunding18D - balance.lastFunding).mul18D(balance.size); //
        int128 newQuote = _quote + balance.quoteBalance - funding;
        int128 newSize = balance.size + _matchSize;
        int128 amountToSettle;
        if (balance.size.mul18D(newSize) < 0) {
            amountToSettle = newQuote + newSize.mul18D(int128(_price));
        } else if (newSize == 0) {
            amountToSettle = newQuote;
        }
        accountDeltas[0] = ISpot.AccountDelta(collateralToken, _account, amountToSettle);
        spotEngine.modifyAccount(accountDeltas);
        newQuote = newQuote - amountToSettle;
        return (newQuote, newSize);
    }

    function _validatePrice(OrderSide makerSide, uint128 makerPrice, uint128 takerPrice) internal pure {
        if (makerSide == OrderSide.BUY && makerPrice < takerPrice) {
            revert Errors.Orderbook_InvalidOrderPrice();
        }
        if (makerSide == OrderSide.SELL && makerPrice > takerPrice) {
            revert Errors.Orderbook_InvalidOrderPrice();
        }
    }

    function _verifyUsedNonce(address user, uint64 nonce) internal view {
        if (isNonceUsed[user][nonce]) {
            revert Errors.Orderbook_NonceUsed(user, nonce);
        }
    }

    /// @dev This helper function is used to create an account delta.
    /// @param productIndex Product id
    /// @param account Account address
    /// @param amount Amount of product token
    /// @param quoteAmount Amount of quote
    /// @return Account delta
    function _createAccountDelta(
        uint8 productIndex,
        address account,
        int128 amount,//数量
        int128 quoteAmount // 金额
    ) internal pure returns (IPerp.AccountDelta memory) {
        return
            IPerp.AccountDelta({productIndex: productIndex, account: account, amount: amount, quoteAmount: quoteAmount});
    }
}
