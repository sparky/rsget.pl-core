########### configuration file syntax. ###########

#### changing options ####

# set option statically
option_name = $value;

# set different value for each user
option_name = by_var $user,
	user1 => $value1,
	user2 => $value2,
	user3 => $value3,
	"" => $default;

# set option dynamically
option_name = sub { <create value> };

# refresh dynamic option at most once every $seconds
option_name = sub_cache { <create value> } $seconds;

# cache dynamic option separatelly for each user
option_name = sub_cache { <create $user-specific value> } $seconds, $user;


#### executing some code ####

# cron FUNCTION, PERIOD, (DELAY);
#
# executes FUNCTION every PERIOD seconds
# third argument delays execution for DELAY seconds after every PERIOD

cron { [function body here] } $seconds;
cron { [function body here] } $seconds, $delay;
cron \&some_function, $seconds;

# run every day at 3:00 UTC
cron { ... } 24 * 60 * 60, +3 * 60 * 60;

# run every minute
cron { ... } 60;
# run every, 15 seconds after the other one
cron { ... } 60, +15;


#### hooks ####
# todo


#### special global variables ####
# those variables can be used to dynamically select some behaviour,
# either by using by_var function or in sub {} body

# $user
# owner of the current download session
# "$user", same as $user->{name}

# $session
# current download session
# "$session", same as $session->{id}

# $interface
# current download interface
# "$interface", same as $interface->{name}

# $plugin
# current session handler
# "$plugin", same as $plugin->{id}

# $file
# destination file
# "$file", same as $file->{path}
