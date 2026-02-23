# 源文件管理

- 优先修改 `lib/`、`test/`、`assets/` 与 `docs/` 下的文件；不要覆盖 `_build/`、`deps/` 或发布目录（如 `_build/prod`、`rel`）中的生成文件。
- 修改过的文件在提交前务必运行 `mix format`，并补充验证新行为的测试。
- 若需要新增 schema 迁移，创建 `priv/repo/migrations/*` 文件，但除非工单明确需要执行迁移，否则不要启动它。

## 文档更新
- 在 `docs/` 或 `skills/<name>/SKILL.md` 中记录新的领域模型或信号流程，以支持自演化 agent。确保这些文档被相关需求或架构计划引用。

## 前端资源
- 若改动静态资源，编辑 `assets/` 下的文件，并在可用时运行 `npm run lint`/`npm run test`，然后再通过 `npm run deploy` 重新构建。
- 不要手动修改 `priv/static` 中生成的文件，它们必须由部署步骤自动产出。
