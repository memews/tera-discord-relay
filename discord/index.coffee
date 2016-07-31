Discord = require 'discord.js'
IPC = require './ipc'
emoji = require './lib/emoji.min'

config = require './config.json'

# vars #
bot = new Discord.Client autoReconnect: true
server = null
channel = null
entry = null
guildRole = null
userlist = {}

# helpers #
escapeRegExp = (s) -> s.replace /[-/\\^$*+?.()|[\]{}]/g, '\\$&'

unHtml = (s) ->
  s
    .replace /<.*?>/g, ''
    .replace /&quot;/gi, '"'
    .replace /&amp;/gi, '&'
    .replace /&lt;/gi, '<'
    .replace /&gt;/gi, '>'

emojify = (s) ->
  emoji.colons_mode = false
  emoji.replace_mode = 'unified' # use unicode replacement
  emoji.inits.env = 1 # hack to ensure replace_mode isn't overwritten
  emoji.replace_colons s

unemojify = do ->
  shortcuts =
    broken_heart: '</3'
    confused: ':-/'
    frowning: ':('
    heart: '<3'
    hearts: '<3'
    neutral_face: ':|'
    open_mouth: ':o'
    smile: ':D'
    smiley: ':)',
    stuck_out_tongue: ':P'
    sunglasses: '8)'
    unamused: ':s'
    wink: ';)'
  regex = new RegExp ':(' + (Object.keys(shortcuts).join '|') + '):', 'gi'

  return (s) ->
    emoji.colons_mode = true
    emoji.replace_unified(s).replace regex, (_, $1) -> shortcuts[$1.toLowerCase()]

# ipc #
path = config['socket-name']
if process.platform is 'win32'
  path = '\\\\.\\pipe\\' + path
else
  path = "/tmp/#{path}.sock"

ipc = new IPC.server path, (event, args...) ->
  return if !channel?

  switch event
    when 'chat'
      [author, message] = args

      # convert HTML to text
      message = unHtml message

      # convert @mention
      # first - nicknames
      for user in server.members
        d = server.detailsOf user
        if d.nick?
          regexp = new RegExp ('@' + escapeRegExp d.nick), 'gi'
          message = message.replace regexp, user.mention()

      # second - usernames
      for user in server.members
        regexp = new RegExp ('@' + escapeRegExp user.username), 'gi'
        message = message.replace regexp, user.mention()

      # convert #channel
      for ch in server.channels when ch.type is 'text'
        regexp = new RegExp (escapeRegExp '#' + ch.name), 'gi'
        message = message.replace regexp, ch.mention()

      # send
      bot.sendMessage channel, "[#{author}]: #{emojify message}"

    when 'guild'
      [motd, names] = args
      names.sort (a, b) -> a.localeCompare b
      bot.setChannelTopic channel, "Online: #{names.join ', '} // MotD: #{emojify unHtml motd}"

    when 'sysmsg'
      [message] = args
      bot.sendMessage channel, message

  return

# bot #
bot.on 'ready', ->
  console.log 'connected as %s (%s)', bot.user.username, bot.user.id

  server = bot.servers.get 'id', config['server-id']
  if !server?
    console.error 'server "%s" not found', config['server-id']
    console.error 'servers:'
    for s in bot.servers
      console.error '- %s (%s)', s.name, s.id
    bog.logout()
    return

  channel = server.channels.get 'name', config['gchat-channel']
  if !channel?
    console.error 'gchat channel "%s" not found', config['gchat-channel']
    bot.logout()
    return

  entry = server.channels.get 'name', config['entry-channel']
  if !entry?
    console.warn 'entry channel "%s" not found', config['entry-channel']

  botRoles = server.rolesOfUser bot.user
  # guild role is the first role that the bot does not have with explicit read to the channel
  for overwrite in channel.permissionOverwrites when overwrite.type is 'role'
    if 'readMessages' in overwrite.allowed
      if not (botRoles.some (role) -> role.id is overwrite.id)
        r = server.roles.get 'id', overwrite.id
        console.log 'using guild role %s (%s)', r.name, r.id
        guildRole = r.id

  if !guildRole?
    console.log 'guild role not found'
    bot.logout()
    return

  console.log 'fetching users...'
  for user in server.members
    roles = server.rolesOfUser user
    if (roles.some (role) -> role.id is guildRole)
      userlist[user.id] = (user.status isnt 'offline')

  for overwrite in channel.permissionOverwrites when overwrite.type is 'member'
    if 'readMessages' in overwrite.denied
      delete userlist[overwrite.id]

  bot.setStatus 'online', 'TERA'
  console.log 'routing to #%s (%s)', channel.name, channel.id

  ipc.send 'fetch'

bot.on 'message', (message) ->
  return unless message.channel.equals channel
  return if message.author.equals bot.user

  str = unemojify message.content
    .replace /<@!?(\d+)>/g, (_, mention) ->
      m = server.members.get 'id', mention
      d = server.detailsOf m
      '@' + (d?.nick or m?.username or '(???)')
    .replace /<#(\d+)>/g, (_, mention) ->
      m = server.channels.get 'id', mention
      '#' + (m?.name or '(???)')

  u = message.author
  d = server.detailsOf u
  author = d?.nick or u?.username or '(???)'
  ipc.send 'chat', author, str

bot.on 'serverNewMember', (eventServer, user) ->
  if entry? and eventServer.equals server
    bot.sendMessage entry, "@everyone please give #{user} a warm welcome!"

bot.on 'serverMemberUpdated', (eventServer, user) ->
  if eventServer.equals server
    roles = server.rolesOfUser user
    if (roles.some (role) -> role.id is guildRole)
      if !userlist[user.id]?
        userlist[user.id] = (user.status isnt 'offline')
        ipc.send 'info', "@#{user.username} joined ##{channel.name}"

bot.on 'userUpdated', (oldUser, newUser) ->
  d = server.detailsOf newUser
  return if d? and d.nick?
  return if oldUser.username is newUser.username
  ipc.send 'info', "@#{oldUser.username} changed name to @#{newUser.username}"

bot.on 'disconnected', ->
  console.log 'disconnected'
  process.exit()

bot.on 'warn', (warn) ->
  console.warn warn

console.log 'connecting...'
bot.login config['email'], config['password']
