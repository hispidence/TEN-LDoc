--------------
-- Handling markup transformation.
-- Currently just does Markdown, but this is intended to
-- be the general module for managing other formats as well.

require 'pl'
local doc = require 'ldoc.doc'
local utils = require 'pl.utils'
local prettify = require 'ldoc.prettify'
local quit, concat, lstrip = utils.quit, table.concat, stringx.lstrip
local markup = {}

-- inline <references> use same lookup as @see
local function resolve_inline_references (ldoc, txt, item, plain)
   local res = (txt:gsub('@{([^}]-)}',function (name)
      local qname,label = utils.splitv(name,'%s*|')
      if not qname then
         qname = name
      end
      local ref,err = markup.process_reference(qname)
      if not ref then
         err = err .. ' ' .. qname
         if item then item:warning(err)
         else
           io.stderr:write('nofile error: ',err,'\n')
         end
         return '???'
      end
      if not label then
         label = ref.label
      end
      if not plain then -- a nastiness with markdown.lua and underscores
         label = label:gsub('_','\\_')
      end
      local html = ldoc.href(ref) or '#'
      label = label or '?que'
      local res = ('<a href="%s">%s</a>'):format(html,label)
      return res
   end))
   return res
end

-- for readme text, the idea here is to create module sections at ## so that
-- they can appear in the contents list as a ToC.
function markup.add_sections(F, txt)
   local sections, L = {}, 1
   for line in stringx.lines(txt) do
      local title = line:match '^##[^#]%s*(.+)'
      if title then
         title = title:gsub('##$','')
         sections[L] = F:add_document_section(title)
      end
      L = L + 1
   end
   F.sections = sections
   return txt
end

local function indent_line (line)
   line = line:gsub('\t','    ') -- support for barbarians ;)
   local indent = #line:match '^%s*'
   return indent,line
end

local function non_blank (line)
   return line:find '%S'
end

-- before we pass Markdown documents to markdown, we need to do three things:
-- - resolve any @{refs}
-- - insert any section ids which were generated by add_sections above
-- - prettify any code blocks

local function process_multiline_markdown(ldoc, txt, F)
   local res, L, append = {}, 0, table.insert
   local filename = F.filename
   local err_item = {
      warning = function (self,msg)
         io.stderr:write(filename..':'..L..': '..msg,'\n')
      end
   }
   local get = stringx.lines(txt)
   local getline = function()
      L = L + 1
      return get()
   end
   local line = getline()
   local indent,code,start_indent
   while line do
      line = resolve_inline_references(ldoc, line, err_item)
      indent, line = indent_line(line)
      if indent >= 4 then -- indented code block
         code = {}
         local plain
         while indent >= 4 or not non_blank(line) do
            if not start_indent then
               start_indent = indent
               if line:match '^%s*@plain%s*$' then
                  plain = true
                  line = getline()
               end
            end
            if not plain then
               append(code,line:sub(start_indent))
            else
               append(res, line)
            end
            line = getline()
            if line == nil then break end
            indent, line = indent_line(line)
         end
         start_indent = nil
         if #code > 1 then table.remove(code) end
         code = concat(code,'\n')
         if code ~= '' then
            code, err = prettify.lua(filename,code..'\n',L)
            append(res, code)
            append(res,'</pre>')
         else
            append(res ,code)
         end
      else
         local section = F.sections[L]
         if section then
            append(res,('<a name="%s"></a>'):format(section))
         end
         append(res,line)
         line = getline()
      end
   end
   return concat(res,'\n')
end


function markup.create (ldoc, format)
   local processor
   markup.plain = true
   markup.process_reference = function(name)
      local mod = ldoc.single or ldoc.module
      return mod:process_see_reference(name, ldoc.modules)
   end
   markup.href = function(ref)
      return ldoc.href(ref)
   end

   if format == 'plain' then
      processor = function(txt, item)
         if txt == nil then return '' end
         return resolve_inline_references(ldoc, txt, item, true)
      end
   else
      local ok,formatter = pcall(require,format)
      if not ok then quit("cannot load formatter: "..format) end
      markup.plain = false
      processor = function (txt,item)
         if txt == nil then return '' end
         if utils.is_type(item,doc.File) then
            txt = process_multiline_markdown(ldoc, txt, item)
         else
            txt = resolve_inline_references(ldoc, txt, item)
         end
         txt = formatter(txt)
         -- We will add our own paragraph tags, if needed.
         return (txt:gsub('^%s*<p>(.+)</p>%s*$','%1'))
      end
   end
   markup.resolve_inline_references = function(txt, errfn)
      return resolve_inline_references(ldoc, txt, errfn, markup.plain)
   end
   markup.processor = processor
   prettify.resolve_inline_references = function(txt, errfn)
      return resolve_inline_references(ldoc, txt, errfn, true)
   end
   return processor
end


return markup
