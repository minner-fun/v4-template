// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {console} from "forge-std/console.sol";


import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

/**
 * @title FeeHook
 * @notice 演示 Hook 概念的简单示例 + 交易奖励系统
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

    // ===== afterSwap 案例：交易奖励系统 =====
    
    // 用户积分映射
    mapping(address => uint256) public userPoints;
    
    // 用户交易次数
    mapping(address => uint256) public userSwapCount;
    
    // 总交易量（以绝对值计算）
    uint256 public totalVolumeProcessed;
    
    // 大额交易阈值（超过这个值给双倍积分）
    uint256 public constant LARGE_SWAP_THRESHOLD = 1000 * 1e18; // 1000 tokens
    
    // 事件：记录奖励发放
    event PointsEarned(address indexed user, uint256 points, uint256 totalPoints);
    event LargeSwapBonus(address indexed user, int256 amount);
    event SwapRecorded(address indexed user, int256 amount0, int256 amount1, uint256 swapNumber);

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
    function _beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
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
     * afterSwap - 交易奖励系统案例
     * AMM 完成计算后触发，在这里实现：
     * 1. 记录用户交易数据
     * 2. 根据交易量发放积分
     * 3. 大额交易给予双倍奖励
     * 
     * @param sender 发起交易的用户地址
     * @param delta 交易后的余额变化（amount0, amount1）
     */
    function _afterSwap(
        address sender,
        PoolKey calldata,
        SwapParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) 
        internal
        override
        returns (bytes4, int128)
    {
        // 处理奖励逻辑（拆分到内部函数以避免 stack too deep）
        _processRewards(sender, delta);
        
        // delta 是池子的余额变化，我们不需要改变它
        // 这里返回 0 表示不对最终的记账进行额外修改
        return (BaseHook.afterSwap.selector, int128(0));
    }
    
    /**
     * @dev 内部函数：处理奖励逻辑
     * 拆分函数以避免 stack too deep 错误
     */
    function _processRewards(address sender, BalanceDelta delta) internal {
        // 获取交易的两个token的数量变化
        int256 amount0 = delta.amount0();
        int256 amount1 = delta.amount1();
        
        // 计算交易量（使用绝对值较大的那个）
        uint256 abs0 = _abs(amount0);
        uint256 abs1 = _abs(amount1);
        uint256 swapVolume = abs0 > abs1 ? abs0 : abs1;
        
        // 1. 记录交易次数
        userSwapCount[sender]++;
        
        // 2. 累计总交易量
        totalVolumeProcessed += swapVolume;
        
        // 3. 计算基础积分：每 1 token 交易量 = 1 积分
        uint256 pointsToAward = swapVolume / 1e18; // 假设 18 位小数
        
        // 4. 大额交易奖励：超过阈值给双倍积分
        if (abs0 > LARGE_SWAP_THRESHOLD || abs1 > LARGE_SWAP_THRESHOLD) {
            pointsToAward = pointsToAward * 2; // 双倍积分
            emit LargeSwapBonus(sender, amount0);
        }
        
        // 5. 发放积分
        userPoints[sender] += pointsToAward;
        
        // 6. 发出事件
        emit PointsEarned(sender, pointsToAward, userPoints[sender]);
        emit SwapRecorded(sender, amount0, amount1, userSwapCount[sender]);
        
        // 7. 打印日志（测试用）
        console.log("=== AfterSwap Reward System ===");
        console.log("User:", sender);
        console.log("Points Earned:", pointsToAward);
        console.log("Total Points:", userPoints[sender]);
        console.log("Swap Count:", userSwapCount[sender]);
    }
    
    // ===== 辅助函数 =====
    
    /**
     * @dev 计算绝对值
     */
    function _abs(int256 value) internal pure returns (uint256) {
        return value >= 0 ? uint256(value) : uint256(-value);
    }
    
    /**
     * @dev 查询用户的奖励统计
     */
    function getUserRewardStats(address user) external view returns (
        uint256 points,
        uint256 swapCount
    ) {
        return (userPoints[user], userSwapCount[user]);
    }
}
