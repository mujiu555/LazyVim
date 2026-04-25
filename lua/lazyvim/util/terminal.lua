---@class lazyvim.util.terminal
local M = {}
local term_command_created = false

---@return string
local function root_dir()
  return LazyVim.root()
end

---@param id integer
---@param create? boolean
---@return snacks.win? terminal
local function get_root_terminal(id, create)
  return Snacks.terminal.get(nil, { cwd = root_dir(), count = id, create = create })
end

---@return integer[]
local function list_root_terminal_ids()
  local root = root_dir()
  local ids = {} ---@type integer[]
  local seen = {} ---@type table<integer, boolean>
  for _, term in ipairs(Snacks.terminal.list()) do
    local ok, data = pcall(function()
      return vim.b[term.buf].snacks_terminal
    end)
    if ok and data and data.cwd == root and data.cmd == nil then
      local id = tonumber(data.id)
      if id and not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  return ids
end

---@return integer
local function next_root_terminal_id()
  local ids = list_root_terminal_ids()
  local next_id = 1
  for _, id in ipairs(ids) do
    if id == next_id then
      next_id = next_id + 1
    elseif id > next_id then
      break
    end
  end
  return next_id
end

---@param s string
---@return integer?
local function parse_id(s)
  local n = tonumber(s)
  if not n or n < 1 or math.floor(n) ~= n then
    return nil
  end
  return n
end

---@param args string[]
local function term_command(args)
  local action = args[1]
  if action == "new" then
    local id = next_root_terminal_id()
    Snacks.terminal.focus(nil, { cwd = root_dir(), count = id })
    LazyVim.info(("Terminal %d opened"):format(id), { title = "Term" })
    return
  end

  if action == "switch" then
    local id = parse_id(args[2] or "")
    if not id then
      return LazyVim.error("Usage: :Term switch <id>", { title = "Term" })
    end
    Snacks.terminal.focus(nil, { cwd = root_dir(), count = id })
    return
  end

  if action == "delete" then
    local id = parse_id(args[2] or "")
    if not id then
      return LazyVim.error("Usage: :Term delete <id>", { title = "Term" })
    end
    local term = get_root_terminal(id, false)
    if not (term and term:buf_valid()) then
      return LazyVim.warn(("Terminal %d not found"):format(id), { title = "Term" })
    end
    vim.api.nvim_buf_delete(term.buf, { force = true })
    return
  end

  local usage = {
    "Usage: :Term <new|switch|delete> [id]",
    "Examples:",
    "  :Term new",
    "  :Term switch 2",
    "  :Term delete 2",
  }
  return LazyVim.info(usage, { title = "Term" })
end

function M.setup_command()
  if term_command_created then
    return
  end
  vim.api.nvim_create_user_command("Term", function(opts)
    term_command(opts.fargs)
  end, {
    nargs = "*",
    complete = function(arg_lead, cmd_line)
      if cmd_line:match("^%s*%S+%s+switch%s+") or cmd_line:match("^%s*%S+%s+delete%s+") then
        return vim.tbl_filter(function(item)
          return item:find("^" .. vim.pesc(arg_lead))
        end, vim.tbl_map(tostring, list_root_terminal_ids()))
      end
      if cmd_line:match("^%s*%S+%s*%S*$") then
        return vim.tbl_filter(function(item)
          return item:find("^" .. vim.pesc(arg_lead))
        end, { "new", "switch", "delete" })
      end
      return {}
    end,
    desc = "Manage numbered root terminals with Snacks.terminal",
  })
  term_command_created = true
end

---@param shell? string
function M.setup(shell)
  vim.o.shell = shell or vim.o.shell

  -- Special handling for pwsh
  if shell == "pwsh" or shell == "powershell" then
    -- Check if 'pwsh' is executable and set the shell accordingly
    if vim.fn.executable("pwsh") == 1 then
      vim.o.shell = "pwsh"
    elseif vim.fn.executable("powershell") == 1 then
      vim.o.shell = "powershell"
    else
      return LazyVim.error("No powershell executable found")
    end

    -- Setting shell command flags
    vim.o.shellcmdflag =
      "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy RemoteSigned -Command [Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new();$PSDefaultParameterValues['Out-File:Encoding']='utf8';$PSStyle.OutputRendering='plaintext';Remove-Alias -Force -ErrorAction SilentlyContinue tee;"

    -- Setting shell redirection
    vim.o.shellredir = '2>&1 | %%{ "$_" } | Out-File %s; exit $LastExitCode'

    -- Setting shell pipe
    vim.o.shellpipe = '2>&1 | %%{ "$_" } | tee %s; exit $LastExitCode'

    -- Setting shell quote options
    vim.o.shellquote = ""
    vim.o.shellxquote = ""
  end

  M.setup_command()
end

return M
