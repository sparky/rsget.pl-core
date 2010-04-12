-- 
-- 2010 (c) Przemysław Iskra <sparky@pld-linux.org>
--
--
-- Try to figure out databases and relations between them.
--

-- user information
CREATE TABLE user (
	id		INTEGER PRIMARY KEY,
	-- user name
	name		TEXT NOT NULL,
	-- password, as plain text
	pass		TEXT,

	-- how user can access their files:
	--  local rsget:  file:///path/to/done/
	--  remote rsget:  http://server/path/to/done/
	--  faster remote:  rsync://server/module/path/
	uri		TEXT,

	-- pause, disable everything
	flags		INTEGER NOT NULL
);

-- file group, defines special relations between multiple files
CREATE TABLE file_group (
	id		INTEGER PRIMARY KEY,

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

	-- XXX: I don't remember this one
	line		INTEGER NOT NULL,

	-- quota used, in kb ? or maybe in seconds
	quota		INTEGER NOT NULL,

	-- disable whole group
	flags		INTEGER NOT NULL,

	FOREIGN KEY(user_id) REFERENCES user(id)
);

-- output file information
-- save file node so we'll be able to find it if it's renamed
CREATE TABLE file (
	id		INTEGER PRIMARY KEY,

	-- file name
	name		TEXT,

	-- hard drive node
	node		INTEGER,

	-- full path to file
	path		TEXT,

	-- exact file size
	size		INTEGER,

	-- id of group file belongs to
	group_id	INTEGER NOT NULL,

	-- lower number for higher priority
	priority	REAL NOT NULL,

	-- XXX: I don't remember this one either
	line		INTEGER NOT NULL,

	FOREIGN KEY(group_id) REFERENCES file_group(id)
);



CREATE TABLE uri (
	id		INTEGER PRIMARY KEY,

	-- link as specified by user
	link		TEXT NOT NULL, -- unique ?

	-- link after performing unify()
	resolved_link	TEXT, -- unique ?

	-- key to file table
	file_id		INTEGER,

	-- name as returned by web page or started download
	file_name	TEXT,

	-- larger number meens file name is more likely to be incorrect
	-- 0 for name as returned by Content-Disposition
	-- 1 for full name from web page
	-- 2 for incomplete name
	-- 3 for complete name with some chars changed
	--   (e.g. letters changed to lower case)
	-- 4 for incomplete name with some chars changed
	file_name_strength	INTEGER,

	-- predicted minimal and maximal file size
	size_min	INTEGER,
	size_max	INTEGER,

	-- additional information from web page
	info		TEXT,

	-- error message
	error		TEXT,

	-- options like download password or video quality
	options		TEXT, 

	-- done, disabled, error ?
	flags		INTEGER NOT NULL,

	-- uri priority within file
	priority	REAL NOT NULL,

	-- wtf wa i thinking ?
	line		INTEGER NOT NULL,

	
	FOREIGN KEY(file_id) REFERENCES file(id)
);


-- information about data chunk within file
CREATE TABLE file_part (
	id		INTEGER PRIMARY KEY,

	-- originating uri
	uri_id		INTEGER NOT NULL,

	-- destination file
	file_id		INTEGER NOT NULL,

	-- start and stop positions of data part within file
	start		INTEGER NOT NULL,
	stop		INTEGER,

	-- XXX: probably useless
	data_before	BLOB,
	data_after	BLOB,

	FOREIGN KEY(uri_id) REFERENCES uri(id),
	FOREIGN KEY(file_id) REFERENCES file(id)
);


-- log messages
CREATE TABLE log (
	id		INTEGER PRIMARY KEY,

	-- time in seconds
	time		INTEGER NOT NULL,

	-- plain, info, done, warning, error
	type		INTEGER NOT NULL,

	-- text before actual line (e.g. [RS][eth1])
	header		TEXT NOT NULL,

	-- actual text
	line		TEXT NOT NULL
);


-- getters
CREATE TABLE plugin (
	-- plugin name
	name		TEXT NOT NULL UNIQUE,

	-- md5 of plugin body
	md5		CHAR(32) UNIQUE,

	-- whole plugin body
	body		TEXT NOT NULL UNIQUE,

	-- last updated time
	time		INTEGER NOT NULL,

	-- supported uris
	uris		TEXT
);
