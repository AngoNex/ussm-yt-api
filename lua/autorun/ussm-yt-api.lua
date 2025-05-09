if not SERVER then return end

local JSONToTable = util.JSONToTable
local SetGlobal2Var = SetGlobal2Var
local string_match = string.match
local string_find = string.find
local timer_Simple = timer.Simple
local table_IsEmpty = table.IsEmpty
local math_max = math.max
local CurTime = CurTime
local HTTP = HTTP

local function printf( fmt, ... )
	return print( string.format( fmt, ... ) )
end

local function FindIndexById( tbl, targetId )
  	for i, v in ipairs( tbl ) do
    	if v.id == targetId then
      		return i
    	end
  	end
	return nil
end

local api_adress = nil

local function check_api( adress )
    HTTP( {
        url = adress .. "/status",
        method = "GET",
        success = function( code, body, headers )
            local result = JSONToTable( body )
			if not istable( result ) then printf( "[USSM-YT-API/Error] External api error, check api" ) end
            local status = result.status
            if status then
                api_adress = adress
                printf( "[USSM-YT-API/Info] API connection established" )
            else
                if result.error then
                    printf( "[USSM-YT-API/Error] External api error, " .. result.error )
                else
                    printf( "[USSM-YT-API/Error] External api error, check api" )
                end
            end
        end,
        failed = function( reason )
            printf( "[USSM-YT-API/Error] External api error, api is not responding" )
        end
    } )
end

local function api_query( id, endfunc )
	HTTP( {
		url = api_adress .. "/prepare-download/" .. id,
		method = "GET",
		success = function( code, body, headers )
			local result = JSONToTable( body )
			if not istable( result ) then printf( "[USSM-YT-API/Error] External api error, check api" ) end
            if result.ready then
                ussm.SetStartTime( CurTime() )
				SetGlobal2Var( "ussm-file-path", api_adress .. "/download/" .. result.id )
				if result.duration and endfunc then
					timer_Simple( result.duration, function()
						endfunc()
					end)
				end
			end
            if result.error then
                printf( "[USSM-YT-API/Error] External api error, " .. result.error )
            end
		end,
		failed = function( reason )
			HTTP( {
				url = api_adress .. "/status/" .. id,
				method = "GET",
				success = function( code, body, headers )
					local result = JSONToTable( body )
					if not istable( result ) then printf( "[USSM-YT-API/Error] External api error, check api" ) end
					local status = result.status
					if status == "unknown" then
                        printf( "[USSM-YT-API/Error] External api error, unknown request status" )
					elseif status == "cached"  then
                        ussm.SetStartTime( CurTime() )
						SetGlobal2Var( "ussm-file-path", api_adress .. "/download/" .. result.id )
					elseif status == "downloading" then
						api_query( id )
					else
						printf( "[USSM-YT-API/Error] External api error, check api" )
					end
                    if result.error then
                        printf( "[USSM-YT-API/Error] External api error, " .. result.error )
                    end
				end,
				failed = function( reason )
					printf( "[USSM-YT-API/Error] External api error, api is not responding" )
				end
			} )
		end
	} )
end

local function api_prepare( id )
	HTTP( {
		url = api_adress .. "/prepare-download/" .. id,
		method = "GET"
	} )
end

local playlist_info = {}

local function api_loop( index )
	local content = playlist_info["content"]
	if not playlist_info["content"][ index ] then printf( "[USSM-YT-API/Error] External api error, check api" ) return end
	local index = index or 1
	local nextindex = math_max( 1, ( index + 1 ) % #content )
	local save = content[ index ].id
	api_prepare( content[ nextindex ].id )
	api_query( save, function()
		local content = playlist_info["content"]
		if not content then return end
		if content[ index ].id ~= save then return end
		api_loop( nextindex )
	end )
end

function ussm.SetFilePath( filePath )
	if not filePath or filePath == "" or filePath == "none" or filePath == "nil" then
		SetGlobal2Var( "ussm-start-time", nil )
		SetGlobal2Var( "ussm-file-path", nil )
		playlist_info = {}
		return
	end

	local domain = string_match( filePath, "^https?://([^/]+)" )
    if domain then
		domain = domain:lower()
		local id = nil
		local listid = nil
		if string_find( domain, "youtube%.com$" ) then
			id = string_match( filePath, "[?&]v=([%w_-]+)" )
			listid = string_match( filePath, "list=([%w%-_]+)" )

			if listid and api_adress then
				HTTP( {
					url = api_adress .. "/playlist/" .. listid,
					method = "GET",
					success = function( code, body, headers )
						local result = JSONToTable( body )
						if not istable( result ) then printf( "[USSM-YT-API/Error] External api error, check api" ) end
						playlist_info = result
						local content = playlist_info.content
						if content then
							if table_IsEmpty( content ) and id then
								api_query( id )
								return
							elseif table_IsEmpty( content ) then
								printf( "[USSM-YT-API/Error] External api error, invalid playlist" )
								return
							else
								printf( "[USSM-YT-API/Info] Playlist successfully received, starting playback" )
								api_loop( id and FindIndexById( playlist_info.content, id ) or 0 )
							end
						end
					end,
					failed = function( reason )
						printf( "[USSM-YT-API/Error] External api error, api is not responding" )
					end
				} )
			end
		end

		if string_find( domain, "youtu%.be$" ) then
			id = string_match( filePath, "youtu%.be/([%w_-]+)" )
		end

		if id and api_adress and not listid then
			api_query( id )
		elseif not listid then
			SetGlobal2Var( "ussm-start-time", CurTime() )
			SetGlobal2Var( "ussm-file-path", filePath )
		end
	end
end

local api_cvar = CreateConVar( "sv_ussm_api", "", bit.bor( FCVAR_ARCHIVE, FCVAR_PROTECTED ), "URL address of the deployed external api." )
check_api( api_cvar:GetString() )

cvars.AddChangeCallback( api_cvar:GetName(), function( _, __, value )
	check_api( value )
end )
