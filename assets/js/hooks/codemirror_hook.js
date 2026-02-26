/**
 * CodeMirror 6 Hook for Cortex
 */
import { EditorView, basicSetup } from "codemirror";
import { EditorState } from "@codemirror/state";
import { keymap } from "@codemirror/view";
import { defaultKeymap } from "@codemirror/commands";
import { elixir } from "codemirror-lang-elixir";
import { javascript } from "@codemirror/lang-javascript";
import { python } from "@codemirror/lang-python";
import { markdown } from "@codemirror/lang-markdown";
import { json } from "@codemirror/lang-json";
import { html } from "@codemirror/lang-html";
import { css } from "@codemirror/lang-css";

// 语言映射
const languageMap = {
  elixir: elixir(),
  javascript: javascript(),
  typescript: javascript({ typescript: true }),
  python: python(),
  markdown: markdown(),
  json: json(),
  html: html(),
  css: css(),
};

export const CodeMirrorHook = {
  mounted() {
    const initialContent = this.el.dataset.content || "";
    const language = this.el.dataset.language || "plaintext";
    
    // 创建编辑器
    this.view = new EditorView({
      state: EditorState.create({
        doc: initialContent,
        extensions: [
          basicSetup,
          keymap.of(defaultKeymap),
          languageMap[language] || [],
          EditorView.updateListener.of((update) => {
            if (update.docChanged) {
              this.handleContentChange();
            }
          }),
          EditorView.theme({
            "&": {
              height: "100%",
              backgroundColor: "#0f172a", // slate-950
              color: "#e2e8f0", // slate-200
            },
            ".cm-content": {
              fontFamily: "JetBrains Mono, monospace",
              fontSize: "13px",
            },
            ".cm-gutters": {
              backgroundColor: "#1e293b", // slate-900
              color: "#64748b", // slate-500
              border: "none",
            },
            ".cm-activeLineGutter": {
              backgroundColor: "#334155", // slate-700
            },
            ".cm-activeLine": {
              backgroundColor: "#1e293b80", // slate-900 with opacity
            },
            ".cm-selectionBackground": {
              backgroundColor: "#0d948880", // teal-600 with opacity
            },
            "&.cm-focused .cm-selectionBackground": {
              backgroundColor: "#0d9488", // teal-600
            },
            ".cm-cursor": {
              borderLeftColor: "#0d9488", // teal-600
            },
          }),
        ],
      }),
      parent: this.el,
    });

    // 监听后端事件
    this.handleEvent("cm:set_value", ({ value }) => {
      this.setValue(value);
    });

    this.handleEvent("cm:set_language", ({ language }) => {
      this.setLanguage(language);
    });

    // 防抖定时器
    this.contentChangeTimeout = null;
  },

  setValue(content) {
    const transaction = this.view.state.update({
      changes: {
        from: 0,
        to: this.view.state.doc.length,
        insert: content,
      },
    });
    this.view.dispatch(transaction);
  },

  setLanguage(language) {
    const extension = languageMap[language] || [];
    // 重新配置语言扩展
    this.view.dispatch({
      effects: EditorView.reconfigure.of([
        basicSetup,
        keymap.of(defaultKeymap),
        extension,
      ]),
    });
  },

  handleContentChange() {
    clearTimeout(this.contentChangeTimeout);
    this.contentChangeTimeout = setTimeout(() => {
      const content = this.view.state.doc.toString();
      this.pushEvent("content_changed", { content });
    }, 500);
  },

  getSelection() {
    const { from, to } = this.view.state.selection.main;
    if (from === to) return null;
    
    const selectedText = this.view.state.sliceDoc(from, to);
    const fromLine = this.view.state.doc.lineAt(from);
    const toLine = this.view.state.doc.lineAt(to);
    
    return {
      text: selectedText,
      start_line: fromLine.number,
      end_line: toLine.number,
    };
  },

  destroyed() {
    clearTimeout(this.contentChangeTimeout);
    if (this.view) {
      this.view.destroy();
    }
  },
};
