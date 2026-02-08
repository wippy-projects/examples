local graph_builder = require("graph_builder")

--- Data function for the viewer page — loads kinds + namespaces for template
local function handler(context)
    return {
        title = "Registry Graph",
        kinds = graph_builder.list_kinds(),
        namespaces = graph_builder.list_namespaces(),
    }
end

return { handler = handler }
