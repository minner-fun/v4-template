# Fee Hook 实现说明

## 当前实现的问题

当前的 `FeeHook` 实现返回了 `BeforeSwapDelta`，但这**不会**真正从用户收取额外费用。

### 为什么不起作用？

1. `BeforeSwapDelta` 影响的是**池子内部的 swap 计算**，而不是用户支付的金额
2. `SwapRouter.swapExactTokensForTokens()` 只会从用户那里转账 `amountIn`
3. Hook 返回的 delta 不会改变 Router 从用户那里拿走的金额

### 测试结果

```solidity
// 用户调用
swapRouter.swapExactTokensForTokens(1e18, ...);

// 实际转账（从 trace 可以看到）
transferFrom(user, poolManager, 1e18);  // 只转了 1e18，没有额外费用

// 即使 beforeSwap 返回了 delta，也不影响这个转账金额
```

## 正确的收费方式

### 方案 1: 使用 `beforeSwapReturnDelta` 权限 ⭐

需要主动调用 `poolManager` 来收取费用：

```solidity
contract FeeHook is BaseHook {
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            // ...
            beforeSwap: true,
            beforeSwapReturnDelta: true,  // 启用这个权限
            // ...
        });
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 amountIn = params.amountSpecified < 0 
            ? uint256(-params.amountSpecified) 
            : uint256(params.amountSpecified);

        uint256 extraFee = (amountIn * EXTRA_FEE_BPS) / 10000;

        // 确定是哪个 token
        Currency specified = params.zeroForOne ? key.currency0 : key.currency1;

        // 主动收取费用
        specified.take(poolManager, address(this), extraFee, false);

        // 返回 delta，表示从指定金额中减少 extraFee
        return (
            BaseHook.beforeSwap.selector,
            toBeforeSwapDelta(int128(uint128(extraFee)), 0),  // 注意：这里是正数
            0
        );
    }
}
```

### 方案 2: 使用动态费率（最简单）✅

通过 `lpFeeOverride` 参数修改池子的费率：

```solidity
contract FeeHook is BaseHook {
    function _beforeSwap(
        address,
        PoolKey calldata,
        SwapParams calldata,
        bytes calldata
    ) internal pure override returns (bytes4, BeforeSwapDelta, uint24) {
        // 返回一个动态费率
        // 3000 = 0.3%, 加上额外的 10 bp (0.01%)
        uint24 dynamicFee = 3000 + 10;  // 总共 0.31%
        
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            dynamicFee  // 通过这个参数修改费率
        );
    }
}
```

### 方案 3: 使用 `afterSwapReturnDelta`

在 swap 完成后修改最终结果：

```solidity
contract FeeHook is BaseHook {
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            // ...
            afterSwap: true,
            afterSwapReturnDelta: true,  // 启用这个权限
            // ...
        });
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // 计算额外费用
        int128 specifiedAmount = params.zeroForOne ? delta.amount0() : delta.amount1();
        int128 extraFee = specifiedAmount / 1000;  // 0.1%

        // 确定是哪个 token
        Currency specified = params.zeroForOne ? key.currency0 : key.currency1;

        // 收取额外费用
        specified.take(poolManager, address(this), uint128(extraFee), false);

        // 返回额外的 delta
        return (BaseHook.afterSwap.selector, extraFee);
    }
}
```

## 推荐方案

**方案 2（动态费率）** 是最简单和最符合 Uniswap v4 设计理念的方式：
- ✅ 简单直接
- ✅ 不需要额外的权限
- ✅ 不需要手动管理 token 转账
- ✅ 费用直接归入池子的 LP 费用

如果需要将费用单独收集到 Hook 合约，则使用**方案 1**。

## 参考资料

- [Uniswap v4 Hook 文档](https://docs.uniswap.org/contracts/v4/overview)
- [BeforeSwapDelta 说明](https://github.com/Uniswap/v4-core/blob/main/src/types/BeforeSwapDelta.sol)
- [Dynamic Fee Hook 示例](https://github.com/Uniswap/v4-periphery/tree/main/src/base/hooks)

