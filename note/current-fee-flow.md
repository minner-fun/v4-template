# 当前 FeeHook 实现的实际流程

## 完整的执行流程

```
步骤 1: 用户调用
swapRouter.swapExactTokensForTokens(amountIn: 1e18, ...)

↓

步骤 2: SwapRouter 从用户转账（在调用 hook 之前！）
transferFrom(user, poolManager, 1e18)  ← 只转了 1e18

↓

步骤 3: 调用 PoolManager.swap
params.amountSpecified = -1e18  ← 注意：这是负数，表示 exact input

↓

步骤 4: 触发 beforeSwap hook
计算: extraFee = 1e18 * 10 / 10000 = 1e15
返回: BeforeSwapDelta(-1e15, 0)

↓

步骤 5: 池子内部计算 swap（关键！）
池子看到:
  - 用户指定的金额: -1e18
  - Hook 的 delta: -1e15
  
池子的理解:
  "用户想要精确输入，但 hook 说要减少 1e15 的计算量"
  
实际效果:
  - 池子可能会：
    a) 调整内部的价格计算
    b) 或者影响最终的输出金额
  - 但不会改变"用户已经支付的 1e18"

↓

步骤 6: 返回结果
swapDelta.amount0() = -1e18  ← 用户的余额变化
swapDelta.amount1() = +0.987e18  ← 用户收到的输出
```

## 关键点：用户只支付了 1 次！

### ❌ 错误理解
```
用户支付流程:
1. 第一次扣费: 1e18
2. 第二次扣费: 1e15 (hook 扣的)
总计: 1.001e18  ← 这是错的！
```

### ✅ 实际情况
```
用户支付流程:
1. 唯一一次扣费: 1e18  ← SwapRouter 只转了这么多
2. Hook 的 delta 不扣费  ← 只影响池子内部计算

总计: 1e18  ← 用户只支付了这么多
```

## 详细的资金流向

### 用户的视角（From trace）
```
Before swap:
  user.balance0 = 9999900000000000000000005

SwapRouter 执行转账:
  transferFrom(user, poolManager, 1e18)

After swap:
  user.balance0 = 9999899000000000000000005
  
变化: 1e18 (不是 1.001e18)
```

### BeforeSwapDelta 的作用

`BeforeSwapDelta(-1e15, 0)` 告诉池子的是：

```
"在内部计算时，把 specified amount 减少 1e15"
```

这可能影响：
- 价格滑点计算
- 最终输出金额
- 内部的会计逻辑

但**绝对不会**：
- 从用户额外转账
- 改变用户已支付的金额
- 扣除第二次费用

## 为什么 BeforeSwapDelta 不能收费？

因为执行顺序：

```
1. SwapRouter.transferFrom(user, poolManager, amountIn)  ← 先转账
2. poolManager.unlock()  ← 然后解锁
3. hook.beforeSwap()  ← Hook 此时执行
4. 内部 swap 计算
5. poolManager.settle()  ← 结算
```

当 hook 执行时，钱已经转走了！Hook 返回的 delta 无法改变已经发生的转账。

## 比喻说明

想象你去餐厅：

### 当前实现（BeforeSwapDelta）
```
1. 你先付了 100 元
2. 服务员在后厨记录："减少 10 元的食材"
3. 但你已经付了 100 元，不会再扣钱
4. 可能影响：你的菜分量少了点
```

### 方案 1（beforeSwapReturnDelta + take）
```
1. 你先付了 100 元
2. 服务员说："额外加收 10 元服务费"
3. 你再付 10 元
4. 总计：110 元
```

### 方案 2（动态费率）
```
1. 餐厅价格本来就高一点（110 元）
2. 你付 110 元（觉得是正常价格）
3. 一次付清
```

## 总结

**当前实现**：
- ❌ 不会从用户扣除两次费用
- ❌ 不会让用户额外支付
- ✅ 只影响池子内部的计算逻辑
- ✅ 用户实际只支付了 amountIn (1e18)

**BeforeSwapDelta 的本意**：
用于 Hook 告诉池子"调整你的内部计算"，而不是"从用户收费"。

如果要真正收费，必须使用：
1. `beforeSwapReturnDelta` + 主动调用 `take()`
2. 或修改 `lpFeeOverride` 提高费率

