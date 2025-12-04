# 三种收费场景对比

## 📊 场景对比表

| 特性 | 当前实现 (BeforeSwapDelta) | 方案1 (beforeSwapReturnDelta) | 方案2 (动态费率) |
|------|---------------------------|------------------------------|-----------------|
| **用户支付金额** | 1e18 | 1.001e18 | 1e18 |
| **实际转账次数** | 1 次 | 2 次 | 1 次 |
| **需要额外权限** | ❌ 不需要 | ✅ 需要 beforeSwapReturnDelta | ❌ 不需要 |
| **手续费去向** | 无（不收费） | Hook 合约 | 池子（LP 费用） |
| **是否扣两次费** | ❌ 不扣费 | ✅ 扣两次（1e18 + 1e15） | ❌ 只扣一次，但费率更高 |
| **用户感知** | 正常 swap | 需要额外授权更多代币 | 正常 swap，费率稍高 |

## 场景 1️⃣: 当前实现（BeforeSwapDelta）

```solidity
// ❌ 这个实现不会收费！

function _beforeSwap(...) internal pure override returns (bytes4, BeforeSwapDelta, uint24) {
    uint256 extraFee = (amountIn * 10) / 10000;  // 1e15
    
    return (
        BaseHook.beforeSwap.selector, 
        toBeforeSwapDelta(-int128(uint128(extraFee)), 0),  // ← 只影响池子内部计算
        0
    );
}
```

### 执行流程
```
User Balance: 100 tokens
    ↓ [transferFrom: 1 token]
User Balance: 99 tokens  ← 只扣了 1 次
    ↓ [beforeSwap 返回 delta: -0.001]
    ↓ [影响池子内部计算，不影响用户余额]
User Balance: 99 tokens  ← 还是 99，没有第二次扣费
```

### 结果
- 用户支付：**1 token**
- Hook 收到：**0 token**
- 实际效果：不收费，只影响 swap 计算

---

## 场景 2️⃣: beforeSwapReturnDelta 权限

```solidity
// ✅ 这个会真正收费！

function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        beforeSwap: true,
        beforeSwapReturnDelta: true,  // ← 必须启用
        // ...
    });
}

function _beforeSwap(
    address,
    PoolKey calldata key,
    SwapParams calldata params,
    bytes calldata
) internal override returns (bytes4, BeforeSwapDelta, uint24) {
    uint256 amountIn = params.amountSpecified < 0 
        ? uint256(-params.amountSpecified) 
        : uint256(params.amountSpecified);

    uint256 extraFee = (amountIn * 10) / 10000;  // 1e15

    // 确定是哪个 token
    Currency specified = params.zeroForOne ? key.currency0 : key.currency1;

    // ← 关键：主动从用户收取额外费用
    specified.take(poolManager, address(this), extraFee, false);

    return (
        BaseHook.beforeSwap.selector,
        toBeforeSwapDelta(int128(uint128(extraFee)), 0),  // 注意：这里是正数
        0
    );
}
```

### 执行流程
```
User Balance: 100 tokens
    ↓ [transferFrom: 1 token]  ← 第一次扣费
User Balance: 99 tokens
    ↓ [hook 调用 take: 0.001 token]  ← 第二次扣费
User Balance: 98.999 tokens
    ↓ [继续 swap 计算]
Result: 用户实际支付了 1.001 tokens
```

### 结果
- 用户支付：**1.001 tokens**
- Hook 收到：**0.001 tokens**
- 实际效果：用户确实被扣了两次

### 资金流向
```
1. Router 转走: 1 token    → 到 PoolManager
2. Hook 收取:  0.001 token → 到 Hook 合约
```

---

## 场景 3️⃣: 动态费率

```solidity
// ✅ 最简单的收费方式

function _beforeSwap(...) internal pure override returns (bytes4, BeforeSwapDelta, uint24) {
    // 原费率 3000 (0.3%) + 额外 10 (0.01%) = 3010 (0.31%)
    uint24 dynamicFee = 3010;
    
    return (
        BaseHook.beforeSwap.selector,
        BeforeSwapDeltaLibrary.ZERO_DELTA,  // 不需要 delta
        dynamicFee  // ← 通过这个参数提高费率
    );
}
```

### 执行流程
```
User Balance: 100 tokens
    ↓ [transferFrom: 1 token]  ← 只扣一次
User Balance: 99 tokens
    ↓ [但池子费率更高: 0.31% 而不是 0.3%]
    ↓ [swap 计算时，更多的金额作为费用留在池子]
Result: 用户支付 1 token，但得到的输出更少（因为费率高）
```

### 结果
- 用户支付：**1 token**
- 池子收取：**0.0031 tokens**（其中 0.0001 是额外的）
- 实际效果：费用更高，但对用户透明

### 费用去向
```
全部到池子的 LP 费用池
LP 提供者获得更多手续费收入
```

---

## 🔍 详细对比：用户支付了几次？

### 当前实现
```
❌ 错误理解：扣了两次
✅ 实际情况：只扣了一次 (1 token)

步骤：
1. transferFrom(user → poolManager, 1 token)  ✅ 唯一的扣费
2. beforeSwap 返回 delta                      ❌ 不扣费，只是计算参数
3. swap 内部计算                              ❌ 不扣费
4. 返回结果                                   ❌ 不扣费
```

### beforeSwapReturnDelta
```
✅ 确实扣了两次

步骤：
1. transferFrom(user → poolManager, 1 token)     ✅ 第一次扣费
2. hook.take(poolManager → hook, 0.001 token)   ✅ 第二次扣费
3. swap 内部计算
4. 返回结果
```

### 动态费率
```
❌ 不算扣两次，只是费率更高

步骤：
1. transferFrom(user → poolManager, 1 token)  ✅ 唯一的扣费
2. swap 计算（使用更高的费率 0.31%）
3. 更多的金额留在池子作为费用
```

---

## 💡 总结

你原来的理解：

> "现在的场景呢，就相当于，不需要用户额外支付，只是我们hook手动多扣除了一次用户的手续费。用户的整个swap过程，扣除了两次手续费"

**这个理解是错误的！**

**正确理解**：

当前实现（BeforeSwapDelta）：
- ❌ 不会扣两次
- ❌ 不会多扣费
- ❌ 不会从用户收取额外费用
- ✅ 只影响池子内部的计算逻辑
- ✅ 用户只被扣了 1 次费：amountIn (1e18)

要实现"扣两次费"，必须使用**方案 1**（beforeSwapReturnDelta + take）。

要实现"提高费率"，推荐使用**方案 2**（动态费率）。

