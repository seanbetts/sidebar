import { Bot, Brain, Command, HardDrive, Monitor, Store, User, Wrench } from 'lucide-svelte';

export const PRONOUN_OPTIONS = [
	'he/him',
	'she/her',
	'they/them',
	'he/they',
	'she/they',
	'they/he',
	'they/she',
	'other'
];

export const SETTINGS_SECTIONS = [
	{ key: 'account', label: 'Account', icon: User },
	{ key: 'user', label: 'User', icon: Monitor },
	{ key: 'agent', label: 'Agent', icon: Bot },
	{ key: 'storage', label: 'Storage', icon: HardDrive },
	{ key: 'shortcuts', label: 'Shortcuts', icon: Command },
	{ key: 'memory', label: 'Memory', icon: Brain },
	{ key: 'skills', label: 'Skills', icon: Wrench },
	{ key: 'store', label: 'Skills Store', icon: Store }
];
