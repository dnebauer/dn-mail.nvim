-- LOAD MODULE ONCE ONLY  {{{1
if vim.g.dn_mail_loaded then
	return
end
vim.g.dn_mail_loaded = true

-- DOCUMENTATION  {{{1

---@brief [[
---*dn-mail-nvim.txt*  For Neovim version 0.9  Last change: 2024 January 26
---@brief ]]

---@toc dn_mail.contents

---@mod dn_mail.intro Introduction
---@brief [[
---An auxiliary mail plugin providing:
---• completion of email addresses in eml file address lines using
---  a neomutt alias file
---• re-flow text support
---• folding of quoted text
---• optional use of markdown syntax highlighting for the message body
---  (mapping and command provided)
---• sentence-based text objects (requires "vim-textobj-sentence" plugin)
---• sensible formatting preferences
---• optional re-wrapping of paragraphs (mapping provided).
---
---Address completion is covered in its own section below
---(|dn_mail.address_completion|) while other features are explained in the
---sections on settings (|dn_mail.settings|), mappings (|dn_mail.mappings|)
---and commands (|dn_mail.commands|).
---@brief ]]

---@mod dn_mail.address_completion Address completion

---@brief [[
---This feature assumes a single file is used to store all emails harvested
---from the user's maildirs. The file stores one email address per line in
---standard neomutt alias definitions, for example:
--->
---    alias johnno John Citizen <john@isp.com> # personal email
---<
---The default location of the aliases file is "~/.config/neomutt/aliases" but
---this can be changed by the |dn_mail.dn_alias_file| global variable.
---
---If no aliases file is available, unreadable, or provides no email
---addresses in the expected format, address completion will abort with a
---warning message.
---
---The plugin hooks into vim's user defined completion in buffers with the
---|filetype| "mail" or "notmuch-compose". Address lines are those beginning
---with any of:
---• From:
---• To:
---• Cc:
---• Bcc:
---
---On these lines the user can press |ctrl-x_ctrl-u| to activate address
---completion.
---
---This feature is based on a plugin by Aaron D. Borden at
---https://github.com/adborden/vim-notmuch-address.
---@brief ]]

local dn_mail = {}

-- PRIVATE VARIABLES  {{{1

local sf = string.format

-- PRIVATE FUNCTIONS

-- forward declarations  {{{1
local mail_md_mode
local option
local variable

-- mail_md_mode(mode)  {{{1

---@private
---Format mail message body as markdown.
---@return nil _ No return value
mail_md_mode = function()
	-- only do this once
	if variable("exists", "buffer", "mail_mode_done") then
		return
	end
	variable("set", "buffer", "mail_mode_done", 1)
	-- define syntax group list '@synMailIncludeMarkdown'
	-- • add 'contained' flag to all syntax items in 'syntax/markdown.vim'
	-- • add top-level syntax items in 'syntax/markdown.vim' to
	--   '@synMailIncludeMarkdown' syntax group list
	variable("remove", "buffer", "current_syntax")
	vim.api.nvim_exec2("syntax include @synMailIncludeMarkdown syntax/markdown.vim", {})
	variable("set", "buffer", "current_syntax", "mail")
	-- apply markdown region
	--       keepend: a match with an end pattern truncates any contained
	--                matches
	--         start: markdown region starts after first empty line
	--                • '\n' is newline [see ':h /\n']
	--                • '\_^$' is empty line [see ':h /\_^', ':h /$']
	--                • '\@1<=' means:
	--                  - must still match preceding ('\n') and following
	--                    ('\_^$') atoms in sequence
	--                  - the '1' means only search backwards 1 character for
	--                    the previous match
	--                  - although the following atom is required for a match,
	--                    the match is actually deemed to end before it begins
	--                    [see ':h /zero-width']
	--           end: markdown region ends at end of file
	--   containedin: markdown region can be included in any syntax group in
	--                'mail'
	--      contains: syntax group '@synMailIncludeMarkdown' is allowed to
	--                begin inside region
	--
	-- warning: keep syntax command below enclosed in [[]] rather than "",
	--          because using "" causes the command to fail and markdown syntax
	--          is not applied
	vim.api.nvim_exec2(
		[[syntax region synMailIncludeMarkdown keepend start='\n\@1<=\_^$' end='\%$' containedin=ALL contains=@synMailIncludeMarkdown]],
		{}
	)
	-- notify user
	vim.api.nvim_echo({ { "Using markdown syntax for mail body" } }, true, {})
end

-- option("get", name, {opts})
-- option(operation, name, value|opts, [opts])  {{{1

---@private
---Universal function for option manipulation. There are 2 function
---signatures: one for a get operation, and another for set, append, prepend,
---and remove operations.
---
---The "get" operation returns a table for list- and map-style options, as
---per |vim.opt|. The remaining operations accept table values as per
---|vim.opt|.
---@param operation string Operation to perform (get|set|append|prepend|remove)
---@param name string Name of option to operate upon
---@param arg3 table|string|number|boolean|nil Depends on operation:
---• "get": Optional configuration dict
---• other: Value to set, append, prepend, or remove
---@param arg4 table|string|number|boolean|nil Depends on operation:
---• "get": Not used
---• other: Optional configuration dict
---
---The optional configuration dict has only 1 valid key:
---• {scope} (string): Can be "local" (behaves as `:setlocal`),
---  "global" (behaves as `:setglobal`), or
---  nil (behaves as ":set", see |set-args|)
---@return any|nil _ Depends on operation:
---• "get": Value of option
---• other: nil
option = function(operation, name, arg3, arg4)
	-- functions
	-- • check param is a non-empty string
	local _check_string_param = function(_name)
		assert(
			type(_name) == "string" and string.len(_name) > 0,
			"Expected non-empty string, got " .. type(_name) .. ": " .. tostring(_name)
		)
	end
	-- • check option name
	local _check_option_name = function(_name)
		local ok = pcall(function()
			local _ = vim.opt[_name]
		end)
		assert(ok, "Invalid option name: " .. name)
	end
	-- check params
	-- • operation
	assert(type(operation) == "string", "Expected string, got " .. type(string))
	local valid_operations = { "get", "set", "append", "prepend", "remove" }
	assert(vim.tbl_contains(valid_operations, operation), "Invalid operation: " .. operation)
	-- • name
	_check_string_param(name)
	_check_option_name(name)
	-- • arg3 ('value' or 'opts')
	local opts, value = {}, nil
	local value_types = { "table", "number", "integer", "string", "boolean", "nil" }
	if operation == "get" then
		-- arg3 is 'opts'
		opts = opts or {}
		local valid_arg3_types = { "table", "nil" }
		assert(vim.tbl_contains(valid_arg3_types, type(arg3)), "Expected table, got " .. type(arg3))
		if type(arg3) == "table" then
			for key, val in ipairs(arg3) do
				opts[key] = val
			end
		end
	else
		-- arg3 is 'value'
		assert(vim.tbl_contains(value_types, type(arg3)), "Invalid option value type: " .. type(arg3))
		value = arg3
	end
	-- • arg4 ('opts' or nil)
	if vim.tbl_contains({ "set", "append", "prepend", "remove" }, operation) then
		-- arg4 is 'opts'
		opts = opts or {}
		local valid_arg4_types = { "table", "nil" }
		assert(vim.tbl_contains(valid_arg4_types, type(arg4)), "Expected table, got " .. type(arg4))
		if type(arg4) == "table" then
			for key, val in ipairs(arg4) do
				opts[key] = val
			end
		end
	end
	-- • opts
	for key, val in pairs(opts) do
		if key == "scope" then
			local valid_scopes = { "local", "global" }
			assert(type(val) == "string", "Expected string scope, got " .. type(val))
			assert(vim.tbl_contains(valid_scopes, val), "Invalid scope: " .. val)
		else
			error("Invalid configuration option: " .. key)
		end
	end
	-- get option verb
	local opt_verb = "opt"
	if opts.scope then
		opt_verb = opts.scope
	end
	-- perform operations
	if operation == "get" then
		return vim[opt_verb][name]:get()
	elseif operation == "set" then
		vim[opt_verb][name] = value
	elseif operation == "append" then
		vim[opt_verb][name]:append(value)
	elseif operation == "prepend" then
		vim[opt_verb][name]:prepend(value)
	elseif operation == "remove" then
		vim[opt_verb][name]:remove(value)
	end
end

-- variable(operation, scope, name, [value]) {{{1
---Universal function for vaariable manipulation.
---@param operation string Operation to perform on variable (get, set, exists, remove)
---@param scope string Variable scope (only 'buffer' and 'global' supported)
---@param name string Variable name
---@param value any|nil Variable value (set only)
---@return any|nil _ Return value depends on operation:
---• 'get': any
---• other: nil
variable = function(operation, scope, name, value)
	-- functions
	-- • check param is a non-empty string
	local _check_string_param = function(_name)
		assert(
			type(_name) == "string" and string.len(_name) > 0,
			"Expected non-empty string, got " .. type(_name) .. ": " .. tostring(_name)
		)
	end
	-- check params
	-- • operation
	_check_string_param(operation)
	local valid_operations = { "get", "set", "exists", "remove" }
	assert(vim.tbl_contains(valid_operations, operation), "Invalid operation: " .. operation)
	-- • scope
	_check_string_param(scope)
	local valid_scopes = { "buffer", "global" }
	assert(vim.tbl_contains(valid_scopes, scope), "Invalid operation: " .. scope)
	-- • name
	_check_string_param(name)
	-- • value
	if operation ~= "set" and value ~= nil then
		error("Non-nil value provided for variable" .. operation .. " operation")
	end
	-- perform operation
	local scope_char = { buffer = "b", global = "g" }
	if operation == "get" then
		return vim[scope_char[scope]][name]
	elseif operation == "set" then
		vim[scope_char[scope]][name] = value
	elseif operation == "exists" then
		if scope == "buffer" then
			local ok, _ = pcall(vim.api.nvim_buf_get_var, 0, name)
			return ok
		elseif scope == "global" then
			local ok, _ = pcall(vim.api.nvim_get_var, name)
			return ok
		end
	elseif operation == "remove" then
		vim[scope_char[scope]][name] = nil
	end
end
-- }}}1

-- SETTINGS

---@mod dn_mail.settings Settings

-- alias file  {{{1

---@tag dn_mail.alias_file
---@tag dn_mail.variable_dn_alias_file
---@brief [[
---Path to alias file ~
---
---The global variable "dn_alias_file" contains the absolute path to a file
---containing one email address per line in standard neomutt alias
---definitions.
---
---This plugin needs to access this file to provide address completion, so
---it needs to be specified with the global variable "dn_alias_file" if it
---is not located in the default location.
---
---If there is no alias file address completion will abort with a warning
---message.
---
---Default: $HOME/.config/neomutt/aliases
---@brief ]]

-- re-flow text support  {{{1

---@tag dn_mail.reflow_text
---@tag dn_mail.option_textwidth
---@tag dn_mail.option_formatoptions
---@tag dn_mail.option_comments
---@brief [[
---Reflow text support ~
---
---Support reflowing of content with the following option settings:
---• 'textwidth' = 72
---• 'formatoptions' += "q"
---• 'comments' += "nb:>"
---
---These settings assume the user's mail agent supports reflowing of text,
---e.g., in neomutt the setting "text_flowed" is set to true.
---@brief ]]
option("set", "textwidth", 72, { scope = "local" })
option("append", "formatoptions", "q", { scope = "local" })
option("append", "comments", "nb:>", { scope = "local" })

-- fold quoted text  {{{1

---@tag dn_mail.fold_quoted
---@tag dn_mail.option_foldexpr
---@tag dn_mail.option_foldmethod
---@tag dn_mail.option_foldlevel
---@tag dn_mail.option_foldminlines
---@tag dn_mail.option_colorcolumn
---@brief [[
---Folding of quoted text ~
---
---Support folding of quoted text with the following option settings:
---• 'foldexpr' = "strlen(substitute(matchstr(
---                getline(v:lnum),'\\v^\\s*%(\\>\\s*)+'),'\\s','','g'))"
---• 'foldmethod' = "expr"
---• 'foldlevel' = 1
---• 'foldminlines' = 2
---• 'colorcolumn' = "72"
---
---These settings were taken from the "mutt-trim" github repo README file
---(see https://github.com/Konfekt/mutt-trim).
---@brief ]]
option(
	"set",
	"foldexpr",
	"strlen(substitute(matchstr(getline(v:lnum),'\\v^\\s*%(\\>\\s*)+'),'\\s','','g'))",
	{ scope = "local" }
)
option("set", "foldmethod", "expr", { scope = "local" })
option("set", "foldlevel", 1, { scope = "local" })
option("set", "foldminlines", 2, { scope = "local" })
option("set", "colorcolumn", "72", { scope = "local" })

-- sentence-based text objects  {{{1

---@tag dn_mail.sentence_based_text_objects
---@brief [[
---Sentence-based text objects ~
---
---Sentence-based text objects are more sensible for composing emails.
---If the "preservim/vim-textobj-sentence" plugin is installed, that plugin's
---behaviour is activated by running the "textobj#sentence#init" function.
---See https://github.com/preservim/vim-textobj-sentence for more details.
---@brief ]]
pcall(function()
	vim.fn["textobj#sentence#init"]()
end)

-- sensible formatting preferences  {{{1

---@tag dn_mail.formatting_preferences
---@tag dn_mail.option_formatexpr
---@brief [[
---Formatting preferences ~
---
---The 'formatexpr' option is set to "tqna1".
---@brief ]]
option("set", "formatexpr", "tqna1", { scope = "local" })

-- autolist  {{{1

---@tag dn_mail.autolist
---@tag dn_mail.mapping_<CR>
---@brief [[
---Autolist ~
---
---If the "gaoDean/autolist.nvim" plugin is installed, the |<Enter>| key is
---remapped to trigger that plugin's ":AutolistNewBullet" command. The
---effect of that command is that if the cursor is on a list entry, a new
---list entry is automatically created on the following line.
---See https://github.com/gaoDean/autolist.nvim for more details.
---Note that this mapping may be overridden by other plugins mapping the
---|<Enter>] key.
---@brief ]]
vim.keymap.set("i", "<CR>", "<CR><Cmd>AutolistNewBullet<CR>")
-- }}}1

-- PUBLIC FUNCTIONS

-- all are flagged @private to prevent inclusion in help documentation

-- address_completion(findstart, base)  {{{1

---@private
---A completion function for email addresses. See |complete-functions| for
---details on how these functions are called by vim. Of particular note is
---that the function is called twice for each completion: firstly to find at
---which column completion starts ({findstart} is set to 1 and {base} is
---empty), and secondly to get a list of matches ({findstart} is set to 0
---and {base} is the match string extracted by vim based on the return value
---from the first function call).
---
---The function extracts all alias definitions from the aliases file (either
---the default alias file or one defined by the global variable
---|dn_mail.dn_alias_file|). Email phrases and addresses are then extracted
---from the alias definitions and completion is performed upon them.
---@param findstart integer See |complete-functions| help for "findstart"
---@param base string See |complete-functions| help for "base"
---@return integer|table|nil _ See |complete-functions| help for return values
function dn_mail.address_completion(findstart, base)
	local curline = vim.api.nvim_get_current_line()
	-- only proceed if cursor is in an address line
	local address_fields = { "From", "To", "Cc", "Bcc" }
	local field_matches = vim.tbl_filter(function(field)
		return curline:find(sf("^%s: ", field)) ~= nil
	end, address_fields)
	if vim.tbl_isempty(field_matches) then
		return
	end
	if findstart == 1 then
		-- first call: find where match text, i.e., email address, starts
		local field_delimiter = ": "
		local field_delimiter_start, field_delimiter_end = curline:find(field_delimiter)
		if not field_delimiter_start then
			-- something went wrong!
			return
		end
		local address_begin = field_delimiter_end + 1
		local _, start = unpack(vim.api.nvim_win_get_cursor(0))
		while start > address_begin do
			-- stop backtracking if hit comma, signifying multiple addresses
			-- • may separate addresses with ", "
			if curline:sub(start - 2, start - 1) == ", " then
				break
			end
			-- • may separate addresses with ","
			if curline:sub(start - 1, start - 1) == "," then
				break
			end
			start = start - 1
		end
		-- lua operations above are all 1-based;
		-- because the completefunc mechanism is inherited from vim it requires
		-- the return value to be 0-based (see |complete-functions|),
		-- so must subtract 1 here
		return start - 1
	else
		-- second call: get completion matches
		-- • function to display warning
		local _warn = function(msg)
			vim.api.nvim_echo({ { msg, "WarningMsg" } }, true, {})
		end
		-- • get location of aliases file
		local aliases_file = vim.loop.os_homedir() .. "/.config/neomutt/aliases"
		local ok, user_file = pcall(vim.api.nvim_get_var, "dn_alias_file")
		if ok then
			aliases_file = user_file
		end
		-- • check that the aliases file exists
		if vim.fn.filereadable(aliases_file) == 0 then
			_warn("Cannot locate aliases file: " .. aliases_file)
			return
		end
		-- • slurp alias definitions
		local file = io.open(aliases_file)
		local addresses = {}
		local i = 0
		if file then
			for line in file:lines() do
				i = i + 1
				addresses[i] = line
			end
			file:close()
		else
			_warn(sf("Unable to open file '%s' for reading", aliases_file))
			return
		end
		if vim.tbl_isempty(addresses) then
			_warn(sf("No addresses found in aliases file '%s'", aliases_file))
			return
		end
		-- • extract email phrase and address
		--   - each line is expected to be a standard neomutt alias definition,
		--     for example:
		--     >
		--         alias johnno John Citizen <john@isp.com> # personal email
		--     <
		--   - the alias keyword ('alias'), alias key (e.g., 'johnno') and any terminal
		--     comment (e.g., '# personal email') are stripped, leaving only the email
		--     phrase and address:
		--     >
		--         John Citizen <john@isp.com>
		--     <
		addresses = vim.tbl_map(function(line)
			return line:match("^alias %S+ ([^<]+<[^>]+>).*$")
		end, addresses)
		local base_case_insensitive = base:gsub("%a", function(c)
			return sf("[%s%s]", c:lower(), c:upper())
		end)
		local matches = vim.tbl_filter(function(address)
			return address:match(base_case_insensitive)
		end, addresses)
		return matches
	end
end
option("set", "completefunc", "v:lua.require'dn-mail'.address_completion", { scope = "local" })
-- }}}1

-- MAPPINGS

---@mod dn_mail.mappings Mappings

-- \md = markdown highlighting of message body  {{{1

---@tag dn_mail.markdown_highlighting
---@tag dn_mail.mapping_<Leader>md
---@brief [[
---\md = markdown highlighting of message body ~
---
---Use this mapping in |Normal-mode| and |Insert-mode| to change syntax
---highlighting of the email message body to markdown. This is useful for
---mail programs configured to process the message body to convert markdown
---to html.
---
---Be aware that there is no corresponding mapping or command to reverse
---this change once applied.
---@brief ]]
vim.keymap.set(
	{ "n", "i" },
	"<Leader>md",
	mail_md_mode,
	{ buffer = 0, silent = true, desc = "Use markdown syntax highlighting for message body" }
)

-- <M-q> = rewrap paragraph  {{{1

---@tag dn_mail.rewrap_paragraph
---@tag dn_mail.mapping_<Alt>q
---@brief [[
---<Alt-q> = rewrap paragraph ~
---
---Use "Alt-q" in |Normal-mode| and |Insert-mode| to rewrap the current
---paragraph as per |gq|.
---@brief ]]
vim.keymap.set("n", "<M-q>", '{gq}<Bar>:echo "Rewrapped paragraph"<CR>', { remap = false, silent = true })
vim.keymap.set("i", "<M-q>", "<Esc>{gq}<CR>a", { remap = false, silent = true })
-- }}}1

-- COMMANDS

---@mod dn_mail.commands Commands

-- MUMarkdownFormatting = markdown highlighting of message body  {{{1

---@tag dn_mail.MUMarkdownFormatting
---@brief [[
---MUMarkdownFormatting = markdown highlighting of message body ~
---
---Change the syntax highlighting of the email message body to markdown.
---This is useful for mail programs configured to process the message body
---to convert markdown to html.
---
---Be aware that there is no corresponding mapping or command to reverse
---this change once applied.
---@brief ]]
vim.api.nvim_create_user_command("MUMailMarkdownFormatting", function()
	mail_md_mode()
end, { desc = "Use markdown syntax highlighting for message body" })
-- }}}1

-- note on folding in this file  {{{1

-- cannot add a modeline like "vim:foldmethod=marker:" at the end of the file
-- because some emmylua parsers, like "lemmy-help", will produce null output
-- if there is any file content after the terminal "return" statement;
-- turn on manual folding with "setlocal fdm=marker"
-- }}}1

return dn_mail
