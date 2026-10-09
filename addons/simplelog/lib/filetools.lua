local CreateDirectories = function(path)
    local backSlash = string.byte('\\');
    for c = 1,#path,1 do
        if (path:byte(c) == backSlash) then
            local directory = string.sub(path,1,c);            
            if (ashita.fs.create_directory(directory) == false) then
                gFunc.Error('Failed to create directory: ' .. directory);
                return false;
            end
        end
    end
    return true;
end


local CreateNewProfile = function(path, file_name)
    if ashita.fs.exists(path) then
        gFuncs.Error('Profile already exists: ' .. path);
        return false;
    end

    if (CreateDirectories(path) == false) then        
        return;
    end

    local file = io.open(path, 'w');
    if (file == nil) then
        gFuncs.Error('Failed to access file: ' .. path);
        return false;
    end
	
	local src_profile_path = ('%saddons\\simplelog\\%s.lua'):fmt(AshitaCore:GetInstallPath(), file_name);
	local src_profile_file = io.open(src_profile_path, 'r');
	local src_profile_data = src_profile_file:read('*all');
	file:write(src_profile_data);
	file:close();
	src_profile_file:close();
	return true;
end


local OverwriteProfile = function (path, source_path)
    if (CreateDirectories(path) == false) then
        return;
    end

    if ashita.fs.exists(path) then
        os.remove(path)
    end

    local file = io.open(path, 'w');
    if (file == nil) then
        gFuncs.Error('Failed to access file: ' .. path);
        return false;
    end

	local src_profile_file = io.open(source_path, 'r');
	local src_profile_data = src_profile_file:read('*all');
	file:write(src_profile_data);
	file:close();
	src_profile_file:close();
	return true;
end


-- Formats a settings value the way config.lua stores it.
local SettingToString = function (value)
    if type(value) == "string" then
        return '"'..value..'"'
    end
    return tostring(value)
end

-- Adds a setting the file does not have yet (one introduced after the file was created) to its section.
local InsertSetting = function (file_data, section, key, value)
    local line = '\t\t'..tostring(key)..' = '..SettingToString(value)..',\n'
    local inserted, count = string.gsub(file_data, '('..section..'%s*=%s*T?%s*{[^\n]*\n)', function (header)
        return header..line
    end, 1)
    return count > 0 and inserted or file_data
end

local SaveChanges = function (path, mod_table, file_type)
    if (CreateDirectories(path) == false) then
        return;
    end

    if ashita.fs.exists(path) then
        if type(file_type) == "string" and file_type == 'settings' then
            local file = io.open(path, "r")
            local file_data = file:read('*all')
            file:close()

            for i, v in pairs(mod_table) do
                for n, m in pairs(mod_table[i]) do
                    if i == 'mode' and not file_data:match(tostring(n)..'[%s%S]-[=][%s%S]-[,]') then
                        file_data = InsertSetting(file_data, i, n, m)
                    elseif i == 'mode' then
                        local file_value = file_data:match(tostring(n)..'[%s%S]-[=][%s%S]-[,]')
                        :gsub(tostring(n)..'[%s%S]-[=][%s%S]-', '')
                        :gsub('[,]', '')
                        :gsub(' ', '')

                        if file_value ~= tostring(mod_table[i][n]) then
                            file_data = string.gsub(file_data, tostring(n)..'[%s%S]-[=][%s%S]-[,]\n', tostring(n)..' = '..tostring(mod_table[i][n])..',\n', 1)
                        end
                    end
                end
            end
            -- Opened only once the new contents are ready, so an error above cannot leave the file empty.
            file = io.open(path, "w+")
            file:write(file_data)
            file:close()
        elseif type(file_type) == "string" and file_type == 'filters' then
            local file = io.open(path, "w+")

            file:write('local filters = T{\n')
            for i, v in pairs(mod_table) do
                file:write('	'..tostring(i)..' = {\n')
                for n, m in pairs(mod_table[i]) do
                    if type(m) == "boolean" then
                        file:write('		'..tostring(n)..' = '..tostring(m)..',\n')
                    elseif type(m) == 'table' then
                        file:write('		'..tostring(n)..' = {\n')
                        for g, h in pairs(m) do
                            file:write('		    '..tostring(g)..' = '..tostring(h)..',\n')
                        end
                        file:write('		},\n')
                    end
                end
                file:write('	},\n')
            end
            file:write('};\n')
            file:write('\n')
            file:write('return filters;')
            file:close()
        elseif type(file_type) == "string" and file_type == 'colors' then
            local file = io.open(path, "w+")

            file:write('local colors = T{\n')
            for i, v in pairs(mod_table) do
                file:write('    '..tostring(i)..' = '..tostring(v)..',\n')
            end
            file:write('};\n')
            file:write('\n')
            file:write('return colors;')
            file:close()
        end
        return true
    else
        gFuncs.Error(('File in "%s" dont exist.'):fmt(path))
        return false
    end
end



local exports = {
    CreateDirectories = CreateDirectories,
	CreateNewProfile = CreateNewProfile,
    OverwriteProfile = OverwriteProfile,
    SaveChanges = SaveChanges,
};
return exports;