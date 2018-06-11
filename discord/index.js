// config
const fs = require('fs');
var bot,Discord,IpcModule,ipc,app,botName,gchatChannel;

var healthStatus = false;

function start(config) {
	// set up bot
	const Discord = require('discord.js');
	const bot = new Discord.Client({
	  fetchAllMembers: true,
	  sync: true,
	});

	bot.on('ready', () => {
	  console.log('connected as %s (%s)', bot.user.username, bot.user.id);
	  healthStatus=true
	  bot.user.setActivity({game: {name: "TERA", type: 0}});
	  gchatChannel=bot.guilds.get(config['server-id']).channels.get(config.channels['gchat']);
	});

	bot.on('warn', (warn) => {
	  console.warn(warn);
	});

	bot.on('disconnect', () => {
	  console.log('disconnected');
	  healthStatus=false;
	  process.exit();
	});

	// set up ipc
	const IpcModule = require('./lib/ipc');
	const ipc = new IpcModule(config['socket-name']);

	// set up app
	const app = { bot, ipc };

	console.log('loading submodules...');
	for (let name of ['gchat', 'entry']) {
	  const submodule = require('./lib/' + name);
	  app[submodule] = new submodule(app, config);
	  if ( name == 'gchat' ) {
		gchatModule = submodule;
	  }
	  console.log('- loaded %s', name);
	}

	// connect
	console.log('connecting...');
	bot.login(config['token']).catch((reason) => {
	  console.error('failed to login:', reason);
	  healthStatus=false;
	  process.exit();
	});
}

function healthCheck() {
	return healthStatus;
}

module.exports = {
	start:start,
	healthCheck:healthCheck,
	isRelog:isRelog
}