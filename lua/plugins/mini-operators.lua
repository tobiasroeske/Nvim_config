return {
  {
    "nvim-mini/mini.operators",
    version = false,
    config = function()
      local operators = require("mini.operators")

      -- Keine automatischen Replace-Mappings mit gr erzeugen
      operators.setup({
        replace = { prefix = "" },
      })

      -- Eigene Mappings für Replace
      operators.make_mappings("replace", {
        textobject = "cr",
        line = "crr",
        selection = "cr",
      })
    end,
  },
}
