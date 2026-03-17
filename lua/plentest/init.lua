local Job = require('plentest.job')

local plentest_dir = vim.fn.fnamemodify(debug.getinfo(1).source:match('@?(.*[/\\])'), ':p:h:h:h')

local M = {}

local print_output = vim.schedule_wrap(function(_, ...)
  for _, v in ipairs({ ... }) do
    io.stdout:write(tostring(v))
    io.stdout:write('\n')
  end

  vim.cmd([[mode]])
end)

local function test_paths(paths, opts)
  local minimal = not opts or not opts.init or opts.minimal or opts.minimal_init

  opts = vim.tbl_deep_extend('force', {
    nvim_cmd = vim.v.progpath,
    winopts = { winblend = 3 },
    sequential = false,
    keep_going = true,
    timeout = 50000,
  }, opts or {})

  vim.env.PLENTEST_TIMEOUT = opts.timeout

  local res = {}

  local outputter = print_output

  local path_len = #paths
  local failure = false

  local jobs = vim.tbl_map(function(p)
    local args = {
      '--headless',
      '-c',
      'set rtp+=.,' .. vim.fn.escape(plentest_dir, ' '),
    }

    if minimal then
      table.insert(args, '--noplugin')
      if opts.minimal_init then
        table.insert(args, '-u')
        table.insert(args, opts.minimal_init)
      end
    elseif opts.init ~= nil then
      table.insert(args, '-u')
      table.insert(args, opts.init)
    end

    table.insert(args, '-c')
    table.insert(args, string.format('lua require("busted").run("%s")', vim.fs.abspath(p)))

    local job = Job:new({
      command = opts.nvim_cmd,
      args = args,

      -- Can be turned on to debug
      on_stdout = function(_, data)
        if path_len == 1 then
          outputter(res.bufnr, data)
        end
      end,

      on_stderr = function(_, data)
        if path_len == 1 then
          outputter(res.bufnr, data)
        end
      end,

      on_exit = vim.schedule_wrap(function(j_self, _, _)
        if path_len ~= 1 then
          outputter(res.bufnr, unpack(j_self:stderr_result()))
          outputter(res.bufnr, unpack(j_self:result()))
        end

        vim.cmd('mode')
      end),
    })
    job.nvim_busted_path = p
    return job
  end, paths)

  for _, j in ipairs(jobs) do
    outputter(res.bufnr, 'Scheduling: ' .. j.nvim_busted_path)
    j:start()
    if opts.sequential then
      if not Job.join(j, opts.timeout) then
        failure = true
        pcall(function()
          j.handle:kill(15) -- SIGTERM
        end)
      else
        failure = failure or j.code ~= 0 or j.signal ~= 0
      end
      if failure and not opts.keep_going then
        break
      end
    end
  end

  if not opts.sequential then
    table.insert(jobs, opts.timeout)
    Job.join(unpack(jobs))
    table.remove(jobs, #jobs)
    failure = vim.iter(jobs):any(function(v)
      return v.code ~= 0
    end)
  end
  vim.wait(100)

  if failure then
    return vim.cmd('1cq')
  end

  return vim.cmd('0cq')
end

function M.test_directory(directory, opts)
  print('Starting...')
  local paths = vim.fs.find(function(name)
    return vim.glob.to_lpeg('*_spec.lua'):match(name)
  end, { path = directory, type = 'file', limit = math.huge })

  test_paths(paths, opts)
end

function M.test_file(filepath)
  test_paths({ filepath })
end

return M
