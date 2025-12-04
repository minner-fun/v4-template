// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

/**
 * @title FeeHook
 * @notice 演示 Hook 概念的简单示例
 * 
 * ⚠️ 注意：这是一个演示性的实现
 * 当前的 BeforeSwapDelta 返回值不会真正从用户收取额外费用。
 * 要实现真正的收费功能，需要：
 * 1. 使用 beforeSwapReturnDelta 权限并主动调用 poolManager.take()
 * 2. 或使用动态费率机制（getDynamicSwapFee）
 * 3. 或在 afterSwap 中修改最终的 delta
 */
contract FeeHook is BaseHook {
    // 额外抽取的费率 = 0.1% = 10 basis points (1 bp = 0.01%)
    uint256 public constant EXTRA_FEE_BPS = 10; // 10 bp = 0.1%

    constructor(IPoolManager _manager) BaseHook(_manager) {}

    // 启用 beforeSwap + afterSwap
    function getHookPermissions() 
        public 
        pure 
        override 
        returns (Hooks.Permissions memory) 
    {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * beforeSwap
     * 在 AMM 定价公式执行之前触发
     * 
     * ⚠️ 注意：返回的 BeforeSwapDelta 会影响池子内部的 swap 计算，
     * 但不会直接从用户那里收取额外费用。
     * SwapRouter 只会从用户那里拿走 amountSpecified 的金额。
     */
    function _beforeSwap(address, PoolKey calldata, SwapParams calldata params, bytes calldata)
        internal
        pure
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // 返回一个动态费率
        // 3000 = 0.3%, 加上额外的 10 bp (0.01%)
        uint24 dynamicFee = 3000 + 10;  // 总共 0.31%
        
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDelta.wrap(0),
            dynamicFee  // 通过这个参数修改费率
        );
    }
    

    /**
     * afterSwap
     * AMM 完成计算后触发，可以根据结果进一步操作
     * 我们在这里把预扣税的 token 记录到 hook 合约余额
     */
    function _afterSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) 
        internal
        pure
        override
        returns (bytes4, int128)
    {
        // delta 是池子的余额变化，我们不需要改变它
        // 这里返回 0 表示不对最终的记账进行额外修改
        return (BaseHook.afterSwap.selector, int128(0));
    }
}
