local M={}
local function equal(a,b)
 if type(a)~=type(b)then return false end
 if type(a)=='number'then return a==a and math.abs(a-b)<=math.max(.0001,math.abs(b)*.00001)end
 return a==b
end
function M.apply(o,rules)
 local original,keys={},{}
 -- Complete preflight before the first write.
 for k,v in pairs(rules)do
  local old=o[k];assert(type(old)==type(v),'Unsupported field '..k)
  if type(old)=='number'then assert(old==old and math.abs(old)<1e12,'Invalid value '..k)end
  original[k]=old;keys[#keys+1]=k
 end
 table.sort(keys)
 local changed=0
 local ok,err=pcall(function()
  for _,k in ipairs(keys)do if not equal(o[k],rules[k])then o[k]=rules[k];changed=changed+1 end end
  for _,k in ipairs(keys)do assert(equal(o[k],rules[k]),'Readback failed '..k)end
 end)
 if not ok then
  local restored=true
  for _,k in ipairs(keys)do local r=pcall(function()o[k]=original[k];assert(equal(o[k],original[k]))end);restored=restored and r end
  error(tostring(err)..'; rollback='..tostring(restored))
 end
 return changed,original
end
function M.restore(o,original)return M.apply(o,original)end
return M
