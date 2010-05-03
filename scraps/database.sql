-- 
-- 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
--
--
-- Try to figure out databases and relations between them.
--

-- common columns:
-- * flags
	-- 0 - active
	-- 1 - done
	-- 2 - disabled, slow stop
	-- 3 - disabled, inmediate stop
	-- 4 - error
	-- 5 - file needs fix

-- user information
CREATE TABLE IF NOT EXISTS %{sql_prefix}user (
	id		INTEGER NOT NULL PRIMARY KEY,

	-- user name
	name		TEXT NOT NULL,

	-- password, as plain text
	pass		TEXT,

	-- see: common flags
	flags		INTEGER NOT NULL
);


-- file group, defines special relations between multiple files
CREATE TABLE IF NOT EXISTS %{sql_prefix}file_group (
	id		INTEGER NOT NULL PRIMARY KEY,

	-- group name
	name		TEXT,

	-- group subpath for files
	path		TEXT,

	-- which user does that belong to
	user_id		INTEGER NOT NULL,

	-- null for root group
	parent_group_id	INTEGER,

	-- lower numbers for higher priority
	priority	REAL NOT NULL,

	-- position of file_group in parent group
	position	INTEGER NOT NULL,

	-- see: common flags
	flags		INTEGER NOT NULL,

	-- creation time
	time_start	INTEGER NOT NULL,

	-- time (epoch) of last change in this file_group
	-- [file/group added/removed, changed some internal value]
	time_update	INTEGER NOT NULL,


	FOREIGN KEY(user_id) REFERENCES %{sql_prefix}user(id)
);


-- output file information
-- save file node so we'll be able to find it if it's renamed
CREATE TABLE IF NOT EXISTS %{sql_prefix}file (
	id		INTEGER NOT NULL PRIMARY KEY,

	-- file name
	name		TEXT,

	-- hard drive node
	node		INTEGER,

	-- full path to file
	path		TEXT,

	-- exact file size
	size		INTEGER,

	-- best file_name returned so far
	file_name	TEXT,

	-- same as uri( file_name_strength )
	file_name_strength	INTEGER,

	-- simplified best name, to be able to quickly find clones
	file_name_simplified	TEXT,

	-- largest size_min of all uri
	size_min	INTEGER,
	-- smallest size_max of all uri
	size_max	INTEGER,

	-- id of group file belongs to
	group_id	INTEGER NOT NULL,

	-- see: common flags
	flags		INTEGER NOT NULL,

	-- lower number for higher priority
	priority	REAL NOT NULL,

	-- position of file in parent file_group
	position	INTEGER NOT NULL,

	-- creation time
	time_start	INTEGER NOT NULL,

	-- time (epoch) of last change in this file
	time_update	INTEGER NOT NULL,


	FOREIGN KEY(group_id) REFERENCES %{sql_prefix}file_group(id)
);


-- file source
CREATE TABLE IF NOT EXISTS %{sql_prefix}uri (
	id		INTEGER NOT NULL PRIMARY KEY,

	-- link as specified by user
	link		TEXT NOT NULL, -- unique ?

	-- link after performing unify()
	resolved_link	TEXT, -- unique ?

	-- getter
	plugin_id	INTEGER,

	-- service returned by getter (normally same as getter name)
	service		TEXT,

	-- key to file table
	file_id		INTEGER,

	-- name as returned by web page or started download
	file_name	TEXT,

	-- larger number means file name is more likely to be incorrect
	-- 0 for name as returned by Content-Disposition
	-- 1 for full name from web page
	-- 2 for incomplete name
	-- 3 for complete name with some chars changed
	--   (e.g. letters changed to lower case)
	-- 4 for incomplete name with some chars changed
	file_name_strength	INTEGER,

	-- size as returned by web page
	size_approx	TEXT,

	-- predicted minimal and maximal file size
	size_min	INTEGER,
	size_max	INTEGER,

	-- as returned by headers
	size		INTEGER,

	-- additional information from web page
	info		TEXT,

	-- error message
	error		TEXT,

	-- options like download password or video quality
	options		TEXT, 

	-- see: common flags
	flags		INTEGER NOT NULL,

	-- uri priority within file
	priority	REAL NOT NULL,

	-- position of uri in file
	position	INTEGER NOT NULL,

	-- creation time
	time_start	INTEGER NOT NULL,

	-- time (epoch) of last change in this uri
	time_update	INTEGER NOT NULL,

	
	FOREIGN KEY(plugin_id) REFERENCES %{sql_prefix}plugin(id),
	FOREIGN KEY(file_id) REFERENCES %{sql_prefix}file(id)
);


-- information about data chunk within file
CREATE TABLE IF NOT EXISTS %{sql_prefix}file_part (
	id		INTEGER NOT NULL PRIMARY KEY,

	-- originating uri
	uri_id		INTEGER NOT NULL,

	-- destination file
	file_id		INTEGER NOT NULL,

	-- start and stop positions of data part within file
	start		INTEGER NOT NULL,
	stop		INTEGER NOT NULL,

	-- creation time
	time_start	INTEGER NOT NULL,

	-- data added for the last time (this will allow calculating
	-- download speed)
	time_data	INTEGER NOT NULL,

	-- time (epoch) of last change in this file_part
	time_update	INTEGER NOT NULL,


	FOREIGN KEY(uri_id) REFERENCES %{sql_prefix}uri(id),
	FOREIGN KEY(file_id) REFERENCES %{sql_prefix}file(id)
);

-- chunks of data that should be written to file, but there was some error
CREATE TABLE IF NOT EXISTS %{sql_prefix}file_part_chunk (
	id		INTEGER NOT NULL PRIMARY KEY,

	-- destination file part
	file_part_id		INTEGER NOT NULL,

	-- start and stop positions of data chunk within file
	start		INTEGER NOT NULL,
	stop		INTEGER NOT NULL,

	-- the actual data
	data		BLOB NOT NULL,


	FOREIGN KEY(file_part_id) REFERENCES %{sql_prefix}file_part(id)
);


-- log messages
CREATE TABLE IF NOT EXISTS %{sql_prefix}log (
	id		INTEGER NOT NULL PRIMARY KEY,

	-- which user does that belong to
	user_id		INTEGER,

	-- time in seconds
	time		INTEGER NOT NULL,

	-- plain, info, done, warning, error
	type		INTEGER NOT NULL,

	-- text before actual line (e.g. [RS][eth1])
	header		TEXT NOT NULL,

	-- actual text
	line		TEXT NOT NULL,

	FOREIGN KEY(user_id) REFERENCES %{sql_prefix}user(id)
);


-- getters
CREATE TABLE IF NOT EXISTS %{sql_prefix}plugin (
	id		INTEGER NOT NULL PRIMARY KEY,

	-- plugin name
	name		VARCHAR(32) NOT NULL,

	-- md5 of plugin body
	md5		CHAR(32) NOT NULL,

	-- whole plugin body
	body		TEXT NOT NULL,

	-- last updated time
	time		INTEGER NOT NULL,

	-- supported uris
	uris		TEXT
);


-- config options and other variables
CREATE TABLE IF NOT EXISTS %{sql_prefix}config (
	-- which user does that belong to
	user		TEXT,

	-- variable name
	-- warning: 'key' word is not allowed in MySQL
	name		TEXT NOT NULL,

	-- variable value
	value		TEXT NOT NULL
);
