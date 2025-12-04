## v4 note

scrapy vs uni v4

solmate v4core的依赖库

### 权限开启，官方推荐这种，明确写出的方式
```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        beforeInitialize: false,
        afterInitialize: false,
        beforeAddLiquidity: true,
        afterAddLiquidity: false,
        beforeRemoveLiquidity: true,
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
```

### 常用命令

```shell
# 运行所有 Fee 测试
forge test --match-contract FeeTest -vvv
# 运行特定测试
forge test --match-test testSwapZeroForOne -vvv
# 运行测试并查看 gas 使用情况
forge test --match-contract FeeTest --gas-report
```

### beforeSwapDelta
返回三个参数，本身的函数选择器，，包含两个代币价格的delta数据，，还有费率