# 3DBuilder

计划开发面向定制家具企业内部的资产生成与方案展示工具，通过图片、文字或图文创建 3D 家具资产，支持跨项目复制与修改，并将选定资产组织成场景演示视频。目标是让报价员和设计人员更快完成定制方案表达；默认本地处理，可按授权与线上调用规则主动选择商业模型生成新家具或优化已有成果，具体边界见 [产品文档](docs/product.md)。

首版产品形态已确定为 B/S，通过浏览器使用。目前只有工程骨架和产品构想，没有可启动的应用。模型引擎、具体应用技术栈和硬件方案尚未确定。

## 当前阶段

先阅读 [文档入口](docs/README.md)，按任务需要了解 [产品范围与候选构想](docs/product.md) 和 [工程现状](docs/architecture.md)。当前仍在产品头脑风暴与范围细化阶段，讨论集中维护在产品文档中；具体范围和待确认问题以该文档为准。项目协作约定见 [AGENTS.md](AGENTS.md)。

| 位置 | 内容 |
| --- | --- |
| [docs/README.md](docs/README.md) | 阅读路径、主要维护位置、任务和设计记录规则 |
| `src/`、`tests/` | 应用代码与测试，尚未实现 |
| `scripts/` | 仓库检查与检查器自检 |

## 检查

需要 PowerShell 7，无需第三方模块。在项目根目录运行：

```powershell
pwsh -NoProfile -File scripts/check.ps1
```

输出 `Repository checks passed` 且退出码为 `0` 表示通过；发现问题返回 `1`。找不到 `pwsh` 时，安装 PowerShell 7 或将已有安装加入 PATH。

当前检查必需文件、自有文档的简单本地链接、文本格式、PowerShell 语法，以及任务与设计记录的命名、日期、状态、章节和替代关系。本地链接解析后必须仍在仓库内；指向仓库外路径时，即使本机上该路径存在也判为失败。检查范围为根目录文档与格式配置，以及 `docs/`、`scripts/`、`.github/`、`src/`、`tests/` 下的 Markdown、PowerShell 和 YAML；不读取第三方技能。脚本只读、不联网，可从其他目录调用，也可用 `-Root` 检查临时副本。

修改检查器时，运行其回归自检；CI 同时运行两条命令：

```powershell
pwsh -NoProfile -File scripts/check-selftest.ps1
```

自检在系统临时目录建立副本，覆盖正常记录及格式、语法、链接和记录状态错误，结束后清理副本。输出 `Checker self-tests passed` 且退出码为 `0` 表示通过；失败返回 `1`。它不修改工作区文档。

不检查外部链接、Markdown 锚点、引用式或复杂链接、YAML 语义、秘密泄露，也不判断文字是否真实、不构建或测试应用。首个业务功能加入时，将真实构建、静态检查和行为测试接入 [CI](.github/workflows/ci.yml)。CI 配置覆盖 Windows / Linux。2026-09-30 的 [GitHub Actions](https://github.com/KonvinZhi/3DBuilder/actions/runs/36677529190) 已在这两个系统上通过；该结果只覆盖仓库骨架和检查器样例。

已安装的技能存放在 `.agents/skills/`，按 [技能分工与接入约定](docs/README.md#技能分工与接入) 使用。
