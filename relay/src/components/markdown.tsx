"use client";
import * as React from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";
import rehypeKatex from "rehype-katex";

interface MarkdownProps {
  text: string;
  className?: string;
}

// Renders chat content as GitHub-flavoured Markdown with KaTeX math.
// Used by the admin conversation viewer and Playground to display assistant
// answers, user messages, and thought blocks. Visual styling lives in
// globals.css under `.markdown-body` so it tracks the MUI theme via CSS vars.
//
// The remark/rehype plugin chain is created once at module scope so React
// doesn't tear down + rebuild it on every keystroke during streaming.
const REMARK_PLUGINS = [remarkGfm, remarkMath];
const REHYPE_PLUGINS = [rehypeKatex];

const COMPONENTS: React.ComponentProps<typeof ReactMarkdown>["components"] = {
  a: ({ href, children, ...rest }) => (
    <a href={href} target="_blank" rel="noreferrer noopener" {...rest}>
      {children}
    </a>
  ),
};

export function Markdown({ text, className }: MarkdownProps) {
  return (
    <div className={className ? `markdown-body ${className}` : "markdown-body"}>
      <ReactMarkdown
        remarkPlugins={REMARK_PLUGINS}
        rehypePlugins={REHYPE_PLUGINS}
        components={COMPONENTS}
      >
        {text}
      </ReactMarkdown>
    </div>
  );
}
