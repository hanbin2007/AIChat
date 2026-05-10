import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render } from "@testing-library/react";
import { Markdown } from "@/components/markdown";

afterEach(cleanup);

describe("Markdown component", () => {
  it("renders a paragraph from plain text", () => {
    const { container } = render(<Markdown text="hello world" />);
    expect(container.querySelector("p")?.textContent).toBe("hello world");
  });

  it("renders bold and italic via standard Markdown", () => {
    const { container } = render(<Markdown text="**bold** and *italic*" />);
    expect(container.querySelector("strong")?.textContent).toBe("bold");
    expect(container.querySelector("em")?.textContent).toBe("italic");
  });

  it("renders GFM tables (remark-gfm pipeline wired)", () => {
    const md = "| h1 | h2 |\n| --- | --- |\n| a | b |";
    const { container } = render(<Markdown text={md} />);
    const ths = container.querySelectorAll("th");
    const tds = container.querySelectorAll("td");
    expect(ths.length).toBe(2);
    expect(tds.length).toBe(2);
    expect(ths[0].textContent).toBe("h1");
    expect(tds[1].textContent).toBe("b");
  });

  it("renders GFM strikethrough", () => {
    const { container } = render(<Markdown text="~~gone~~" />);
    expect(container.querySelector("del")?.textContent).toBe("gone");
  });

  it("renders fenced code blocks with a language class", () => {
    const md = "```ts\nconst x = 1;\n```";
    const { container } = render(<Markdown text={md} />);
    const code = container.querySelector("pre code");
    expect(code).not.toBeNull();
    expect(code?.className).toContain("language-ts");
  });

  it("renders inline code without the language class", () => {
    const { container } = render(<Markdown text="use `foo` here" />);
    const inline = container.querySelector("code");
    expect(inline?.textContent).toBe("foo");
    expect(inline?.className).not.toContain("language-");
  });

  it("renders links with target=_blank and rel safety", () => {
    const { container } = render(<Markdown text="[ok](https://example.com)" />);
    const a = container.querySelector("a")!;
    expect(a.getAttribute("href")).toBe("https://example.com");
    expect(a.getAttribute("target")).toBe("_blank");
    expect(a.getAttribute("rel")).toContain("noreferrer");
    expect(a.getAttribute("rel")).toContain("noopener");
  });

  it("renders inline math via KaTeX (rehype-katex pipeline wired)", () => {
    const { container } = render(<Markdown text="inline $a^2 + b^2 = c^2$ done" />);
    // KaTeX wraps rendered math in a span with the `katex` class.
    const katex = container.querySelector(".katex");
    expect(katex).not.toBeNull();
    // Contains the rendered MathML representation.
    expect(container.querySelector(".katex-mathml")).not.toBeNull();
  });

  it("renders display math ($$…$$) using katex-display layout", () => {
    // remark-math treats a $$…$$ block on its own paragraph as display math.
    const md = "before\n\n$$\nE = mc^2\n$$\n\nafter";
    const { container } = render(<Markdown text={md} />);
    expect(container.querySelector(".katex-display")).not.toBeNull();
  });

  it("does not crash on empty input", () => {
    const { container } = render(<Markdown text="" />);
    expect(container.querySelector(".markdown-body")).not.toBeNull();
  });

  it("renders ordered + unordered lists", () => {
    const md = "- a\n- b\n\n1. one\n2. two";
    const { container } = render(<Markdown text={md} />);
    expect(container.querySelectorAll("ul li").length).toBe(2);
    expect(container.querySelectorAll("ol li").length).toBe(2);
  });
});
