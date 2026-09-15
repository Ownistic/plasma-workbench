.pragma library

function localOnly(markdown) {
    if (typeof markdown !== "string") {
        return ""
    }
    // Qt's Markdown renderer can resolve image URLs. Keep descriptions local-only.
    return markdown
        .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
        .replace(/<img\b[^>]*>/gi, "")
        .replace(/<iframe\b[^>]*>[\s\S]*?<\/iframe>/gi, "")
}
