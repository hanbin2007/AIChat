"use client";

import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";
import rehypeKatex from "rehype-katex";
import Box from "@mui/material/Box";

export function Markdown({ source }: { source: string }) {
  return (
    <Box className="markdown-body">
      <ReactMarkdown
        remarkPlugins={[remarkGfm, remarkMath]}
        rehypePlugins={[[rehypeKatex, { maxExpand: 64, maxSize: 8 }]]}
        disallowedElements={["img", "picture", "source", "video", "audio", "iframe", "object", "embed"]}
        unwrapDisallowed
        components={{
          a: ({ href, children, ...rest }) => (
            <a href={href} target="_blank" rel="noopener noreferrer" {...rest}>
              {children}
            </a>
          ),
        }}
      >
        {source}
      </ReactMarkdown>
    </Box>
  );
}
