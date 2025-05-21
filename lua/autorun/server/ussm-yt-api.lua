local function printf( fmt, ... )
	return print( string.format( fmt, ... ) )
end

---@diagnostic disable-next-line: param-type-mismatch
local api_url = CreateConVar( "ussm_yt_url", "", FCVAR_PROTECTED, "URL address of the deployed external API." )

local play_video

---@param base_url string
---@param video_id integer
---@param on_finish? function
local function queue_failure( base_url, video_id, on_finish )
	http.Fetch( base_url .. "/status/" .. video_id, function( body, size, headers, code )
		if code ~= 200 then
			printf( "[USSM-YTA] API error: wrong status code (%d)", code )
			return
		end

		local result = util.JSONToTable( body, true, true )
		if result == nil then
			printf( "[USSM-YTA] API error: json corrupted" )
			return
		end

		if result.error then
			printf( "[USSM-YTA] API error: %s", result.error )
		end

		local status = result.status
		if status == "cached" then
			---@diagnostic disable-next-line: undefined-global
			ussm.SetFilePath( base_url .. "/download/" .. result.id )
		elseif status == "downloading" then
			play_video( base_url, video_id, on_finish )
		else
			printf( "[USSM-YTA] API error: unknown status" )
		end
	end, function( err_msg )
		printf( "[USSM-YTA] API error: %s", err_msg )
	end )
end

---@param base_url string
---@param video_id integer
---@param on_finish? function
function play_video( base_url, video_id, on_finish )
	printf( "[USSM-YTA] Preparing video '%s', give me a few minutes...", video_id )

	http.Fetch( base_url .. "/prepare-download/" .. video_id, function( body, _, ___, code )
		if code ~= 200 then
			queue_failure( base_url, video_id, on_finish )
			return
		end

		local result = util.JSONToTable( body, true, true )
		if result == nil then
			printf( "[USSM-YT] API error: json corrupted" )
			return
		end

		if result.error then
			printf( "[USSM-YT] API error: %s", result.error )
		end

		if result.ready then
			---@diagnostic disable-next-line: undefined-global
			ussm.SetFilePath( base_url .. "/download/" .. result.id )

			local duration = result.duration
			if on_finish ~= nil and duration ~= nil then
				timer.Create( "USSM-YTA", duration, 1, on_finish )
			end
		end
	end, function()
		queue_failure( base_url, video_id, on_finish )
	end )
end

hook.Add( "USSM::Stop", "USSM-YT-API", function()
	timer.Remove( "USSM-YTA" )
end )

---@param base_url string
---@param videos table
---@param index integer
local function api_loop( base_url, videos, index )
	if videos[ index ] == nil then
		printf( "[USSM-YTA] API error: wrong playlist index" )
		return
	end

	local next_index = math.max( 1, ( index + 1 ) % #videos )
	if index ~= next_index then
		http.Fetch( base_url .. "/prepare-download/" .. videos[ next_index ].id )
	end

	play_video( base_url, videos[ index ].id, function()
		api_loop( base_url, videos, next_index )
	end )
end

---@param base_url string
---@param playlist_id string
---@param video_id? integer
local function play_playlist( base_url, playlist_id, video_id )
	printf( "[USSM-YTA] Preparing playlist '%s', give me a few minutes...", playlist_id )

	http.Fetch( base_url .. "/playlist/" .. playlist_id, function( body, _, __, code )
		if code ~= 200 then
			if video_id == nil then
				printf( "[USSM-YTA] API error: wrong status code (%d)", code )
			else
				play_video( base_url, video_id )
			end

			return
		end

		local playlist = util.JSONToTable( body )
		if playlist == nil then
			printf( "[USSM-YTA] API error: json corrupted" )
			return
		end

		local videos = playlist.content
		if videos == nil or next( videos ) == nil then
			if video_id == nil then
				printf( "[USSM-YTA] API error: playlist is empty" )
			else
				play_video( base_url, video_id )
			end

			return
		end

		printf( "[USSM-YTA] Playlist successfully received, starting playback!" )

		---@diagnostic disable-next-line: undefined-global
		ussm.SetRepeat( false )

		local index = 1
		local video = videos[ index ]

		while video ~= nil do
			if video.id == video_id then
				api_loop( base_url, videos, index )
				return
			end

			index = index + 1
			video = videos[ index ]
		end

		api_loop( base_url, videos, 1 )
	end, function( err_msg )
		printf( "[USSM-YTA] API error: %s", err_msg )
	end )
end

hook.Add( "USSM::Play", "USSM-YT-API", function( file_path )
	timer.Remove( "USSM-YTA" )

	if file_path == nil then
		return
	end

	local domain_name = string.match( file_path, "^https?://([^/]+)" )
	if domain_name == nil then
		return
	end

	local base_url = api_url:GetString()
	if base_url == "" then
		printf( "[USSM-YTA] The external API is not configured, cancelling..." )
		return "none"
	end

	base_url = string.match( base_url, "^(https?://.+)/?" ) or base_url
	domain_name = string.match( domain_name, "^www%.(.+)" ) or domain_name

	if domain_name == "youtube.com" then
		local video_id = string.match( file_path, "[?&]v=([%w_-]+)" )

		local playlist_id = string.match( file_path, "list=([%w%-_]+)" )
		if playlist_id == nil then
			if video_id == nil then
				printf( "[USSM-YTA] API error: video id not found" )
			else
				play_video( base_url, video_id )
			end
		else
			play_playlist( base_url, playlist_id, video_id )
		end

		return "none"
	elseif domain_name == "youtu.be" then
		local video_id = string.match( file_path, "youtu%.be/([%w_-]+)" )
		if video_id == nil then return end
		play_video( base_url, video_id )
	end
end )
