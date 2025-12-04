# Swap 输出计算说明

## 为什么不能硬编码期望输出？

在测试中，你不应该硬编码类似 `amountIn*9869/10000` 这样的期望值，因为 swap 的实际输出取决于多个动态因素。

## Swap 输出的影响因素

### 1️⃣ AMM 公式（Constant Product）

Uniswap v4 使用恒定乘积公式：

```
x * y = k

其中:
- x = reserve0 (token0 的储备量)
- y = reserve1 (token1 的储备量)  
- k = 常数
```

当你 swap token0 → token1：

```
输入: Δx (用户支付的 token0)
输出: Δy (用户收到的 token1)

新的平衡:
(x + Δx) * (y - Δy) = k

求解 Δy:
Δy = y - k / (x + Δx)
   = y - (x * y) / (x + Δx)
   = y * Δx / (x + Δx)
```

### 2️⃣ 费率影响

实际用于 swap 的金额需要扣除费用：

```
费率: 3010 bp = 0.301%

实际用于 swap 的金额:
effectiveAmountIn = amountIn * (1 - 0.00301)
                  = amountIn * 0.99699

输出:
amountOut = y * effectiveAmountIn / (x + effectiveAmountIn)
```

### 3️⃣ 价格滑点

因为流动性有限，大额交易会造成价格滑点：

```
滑点 = (实际价格 - 初始价格) / 初始价格

交易越大，滑点越大
流动性越少，滑点越大
```

### 4️⃣ Tick 系统

Uniswap v4 使用 concentrated liquidity 和 tick 系统，进一步影响价格计算。

## 实际例子分析

### 测试场景

```solidity
// Setup 中创建的流动性
liquidityAmount = 100e18
初始价格 = 1:1 (SQRT_PRICE_1_1)

// 用户 swap
amountIn = 1e18 token0
费率 = 3010 bp (0.301%)
```

### 计算过程

```
步骤 1: 扣除费用
effectiveAmountIn = 1e18 * (1 - 0.00301)
                  = 1e18 * 0.99699
                  = 996990000000000000

步骤 2: AMM 计算（简化）
假设当前储备:
  x (token0) ≈ 100e18
  y (token1) ≈ 100e18

输出:
  Δy = y * effectiveAmountIn / (x + effectiveAmountIn)
     = 100e18 * 0.99699e18 / (100e18 + 0.99699e18)
     = 100e18 * 0.99699e18 / 100.99699e18
     ≈ 0.9871e18

步骤 3: 实际结果（从 trace）
  实际输出 = 987158034397061298
           ≈ 0.98715e18
```

### 损失分析

```
总损失 = 1e18 - 0.9871e18 = 0.0129e18 (1.29%)

分解:
1. 费率损失: 0.301%
2. 滑点损失: ~0.989%

总计: ~1.29%
```

## 正确的测试方法

### ❌ 错误方式

```solidity
// 不要硬编码精确值
assertEq(swapDelta.amount1(), amountIn * 9869 / 10000);  // 错误！
```

**问题**：
- 实际输出 = 987158034397061298
- 期望输出 = 986900000000000000
- 差异虽小，但会导致测试失败

### ✅ 正确方式 1：范围验证

```solidity
uint256 amountOut = uint256(uint128(swapDelta.amount1()));

// 验证输出在合理范围内
assertGt(amountOut, amountIn * 98 / 100, "Should receive at least 98%");
assertLt(amountOut, amountIn, "Should receive less than input due to fees");
```

### ✅ 正确方式 2：相对比较

```solidity
// 如果要测试费率影响，可以比较两次 swap
BalanceDelta delta1 = swap(fee: 3000);  // 0.3% 费率
BalanceDelta delta2 = swap(fee: 3010);  // 0.31% 费率

// 验证更高的费率导致更少的输出
assertLt(delta2.amount1(), delta1.amount1(), "Higher fee should yield less output");
```

### ✅ 正确方式 3：容差范围

```solidity
uint256 expectedOut = calculateExpectedOutput(amountIn, liquidity, fee);
uint256 actualOut = uint256(uint128(swapDelta.amount1()));

// 允许 0.1% 的误差
uint256 tolerance = expectedOut / 1000;
assertApproxEqAbs(actualOut, expectedOut, tolerance, "Output within tolerance");
```

### ✅ 正确方式 4：精确 AMM 计算

如果需要精确验证，实现 AMM 公式：

```solidity
function calculateSwapOutput(
    uint256 amountIn,
    uint256 reserveIn,
    uint256 reserveOut,
    uint24 fee
) internal pure returns (uint256) {
    // 扣除费用
    uint256 amountInWithFee = amountIn * (1000000 - fee) / 1000000;
    
    // AMM 公式
    uint256 numerator = reserveOut * amountInWithFee;
    uint256 denominator = reserveIn + amountInWithFee;
    
    return numerator / denominator;
}

// 测试中使用
uint256 expected = calculateSwapOutput(amountIn, reserve0, reserve1, 3010);
assertApproxEqAbs(actualOut, expected, expected / 1000);
```

## 动态费率测试示例

### 测试费率是否生效

```solidity
function testDynamicFeeWorks() public {
    uint256 amountIn = 1e18;
    
    // 使用默认费率 (3000 bp)
    BalanceDelta deltaDefault = swapWithDefaultFee(amountIn);
    
    // 使用动态费率 (3010 bp)  
    BalanceDelta deltaHigher = swapWithDynamicFee(amountIn);
    
    // 验证更高的费率导致更少的输出
    assertLt(
        uint256(uint128(deltaHigher.amount1())),
        uint256(uint128(deltaDefault.amount1())),
        "Higher fee should yield less output"
    );
    
    // 验证差异在合理范围内（约 0.01%）
    uint256 difference = uint256(uint128(deltaDefault.amount1())) 
                       - uint256(uint128(deltaHigher.amount1()));
    uint256 expectedDifference = amountIn * 10 / 1000000;  // 0.01%
    
    assertApproxEqAbs(difference, expectedDifference, expectedDifference / 10);
}
```

### 测试费率对输出的影响

```solidity
function testFeeImpactOnOutput() public {
    uint256 amountIn = 1e18;
    
    BalanceDelta delta = swapRouter.swapExactTokensForTokens({...});
    
    uint256 amountOut = uint256(uint128(delta.amount1()));
    
    // 计算实际费率影响
    // 如果没有费用和滑点，应该收到 ~1e18
    // 实际收到 ~0.987e18，损失 ~1.3%
    
    uint256 loss = amountIn - amountOut;
    uint256 lossPercentage = (loss * 10000) / amountIn;  // 以 bp 计算
    
    // 验证损失在合理范围内（100-200 bp = 1-2%）
    assertGt(lossPercentage, 100, "Loss should be more than 1%");
    assertLt(lossPercentage, 200, "Loss should be less than 2%");
}
```

## 总结

**关键要点**：

1. ❌ 不要硬编码精确的输出值
2. ✅ 使用范围验证（如 98-99%）
3. ✅ 或者实现精确的 AMM 公式计算
4. ✅ 或者使用相对比较（比较不同费率）
5. ✅ 或者使用容差范围（`assertApproxEqAbs`）

**为什么**：

- Swap 输出受多个因素影响
- 精确值难以预测
- 小的差异不代表错误
- 应该验证"合理性"而不是"精确性"

**你的测试应该关注**：

- ✅ 用户支付了正确的金额
- ✅ 用户收到了合理的输出
- ✅ 费率影响了输出（如果测试费率）
- ✅ Hook 被正确调用
- ❌ 不是精确到 wei 的输出值

