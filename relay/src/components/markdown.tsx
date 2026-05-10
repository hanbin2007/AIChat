"use client";
import * as React from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";
import rehypeKatex from "rehype-katex";
import { cn } from "@/lib/cn";

interface MarkdownProps {
  text: string;
  className?: string;
}

// Renders chat content as GitHub-flavoured Markdown with KaTeX math.
// Used by the admin conversation viewer and Playground to display assistant
// answers, user messages, and thought blocks.
//
// The remark/rehype plugin chain is created once at module scope so React
// doesn't tear down + rebuild it on every keystroke during streaming.
const REMARK_PLUGINS = [remarkGfm, remarkMath];
const REHYPE_PLUGINS = [rehypeKatex];

const COMPONENTS: React.ComponentProps<typeof ReactMarkdown>["components"] = {
  a: ({ href, children, ...rest }) => (
    <a
      href={href}
      target="_blank"
      rel="noreferrer noopener"
      className="text-primary underline underline-offset-2"
      {...rest}
    >
      {children}
    </a>
  ),
  code: ({ className, children, ...rest }) => {
    const isBlock = /language-/.test(className ?? "");
    if (isBlock) {
      return (
        <code className={cn(className, "block")} {...rest}>
          {children}
        </code>
      );
    }
    return (
      <code
        className="rounded bg-surface-container-highest px-1 py-0.5 text-[0.92em] font-mono"
        {...rest}
      >
        {children}
      </code>
    );
  },
  pre: ({ children, ...rest }) => (
    <pre
      className="my-2 overflow-x-auto rounded-m3-sm bg-surface-container-highest p-3 text-m3-body-s font-mono"
      {...rest}
    >
      {children}
    </pre>
  ),
  table: ({ children, ...rest }) => (
    <div className="my-2 overflow-x-auto">
      <table className="w-full border-collapse text-m3-body-s" {...rest}>
        {children}
      </table>
    </div>
  ),
  th: ({ children, ...rest }) => (
    <th className="border border-outline-variant bg-surface-container px-2 py-1 text-left" {...rest}>
      {children}
    </th>
  ),
  td: ({ children, ...rest }) => (
    <td className="border border-outline-variant px-2 py-1 align-top" {...rest}>
      {children}
    </td>
  ),
};

export function Markdown({ text, className }: MarkdownProps) {
  return (
    <div className={cn("markdown-body", className)}>
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
