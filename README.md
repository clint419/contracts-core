# BSX Exchange contracts

[![CI](https://github.com/bsx-exchange/contracts-core/actions/workflows/ci.yml/badge.svg)](https://github.com/bsx-exchange/contracts-core/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/bsx-exchange/contracts-core/graph/badge.svg?token=ACNT7WX68X)](https://codecov.io/gh/bsx-exchange/contracts-core)
[![npm version](https://img.shields.io/npm/v/@bsx-exchange/client/latest.svg)](https://www.npmjs.com/package/@bsx-exchange/client/v/latest)

This repository contains the core smart contracts for BSX Exchange.

## Setup

Requirements:

- Node 18
- Bun ([Installation](https://bun.sh/docs/installation))
- Foundry ([Installation](https://getfoundry.sh))

```bash
$ git clone git@github.com:bsx-exchange/contracts-core.git
$ cd contracts-core
$ bun install
```

## Development

### Linting and Formatting

```bash
$ bun run lint
```

### Testing

Run all tests

```bash
$ bun run test
```

Check contract coverage

```bash
$ bun run test:coverage
```

## Deployments

| Contracts                                    | Base Mainnet                                 |
| -------------------------------------------- | -------------------------------------------- |
| [Exchange](./src/Exchange.sol)               | `0x26A54955a5fb9472D3eDFeAc9B8E4c0ab5779eD3` |
| [ClearingService](./src/ClearingService.sol) | `0x4a7f51E543b9DD6b259bcFD2FA2a3602eBd5679E` |
| [Orderbook](./src/OrderBook.sol)             | `0xE8A973AA7600c1Dba1e7936B95f67A14e6257137` |
| [SpotEngine](./src/Spot.sol)                 | `0x519086cd28A7A38C9701C0c914588DB4040FFCaE` |
| [PerpEngine](./src/Perp.sol)                 | `0xE2EB30975B8d063B38FDd77892F65138Bc802Bc7` |
| [Access](./src/access/Access.sol)            | `0x6c3Bb56d77E4225EEcE45Cde491f4A1a1649B034` |

## License

The primary license for BSX Exchange contracts is the MIT License, see [`LICENSE`](./LICENSE). However, there are
exceptions:

- Many files in `test/` remain unlicensed (as indicated in their SPDX headers).

## 分析学习

1. 每个合约，管理不同的功能，合约之间存在组合依赖关系。
2. 合约需要单独部署，但是repo并没有提供部署脚本。
3. 单元测试通过foundry完成的。
4. package.json 存在没有用的依赖，
5. 权限设计：虽然openzeppelin已经有权限香港的库了，但是是基础的，需要继承过来，进一步设计符合自己项目场景的权限。
6. 编码原则：参数校验、访问级别、合约可升级、漏洞防范等。
7. 参数的校验，要根据接口的开放成都决定，内部接口，就可以减少校验，但是任何人都可以访问的接口方法，就需要权量校验。特别
   是充值接口。

## 业务分析

1、充币：2、提币：是否可以开放一个任何人都可以提币的接口？？？3、匹配交易：为什么现货与永续是合并的接口？？？！！！

## 资料

https://www.bsx.exchange/
