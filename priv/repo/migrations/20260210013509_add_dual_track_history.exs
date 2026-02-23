defmodule Cortex.Repo.Migrations.AddDualTrackHistory do
  use Ecto.Migration

  def change do
    # 为 conversations 表添加双轨历史字段
    alter table(:conversations) do
      # LLM 对话上下文 - 发送给模型的严格格式消息列表
      add :llm_context, :text, default: "[]", null: false

      # 完整历史记录 - 所有事件的审计日志
      add :full_history, :text, default: "[]", null: false
    end

    # SQLite3 不支持 GIN 索引，使用普通索引
    # 注意：SQLite 的 JSON 查询性能不如 PostgreSQL + GIN 索引
    create index(:conversations, [:llm_context])
    create index(:conversations, [:full_history])
  end
end
