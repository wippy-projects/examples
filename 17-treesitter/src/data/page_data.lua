local parser = require("parser")

--- Data function for the viewer page — loads available languages
local function handler(context)
    return {
        title = "Tree-sitter Call Graph",
        languages = parser.list_languages(),
    }
end

return { handler = handler }
