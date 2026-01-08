import { Brain, Command, HardDrive, Monitor, User, Wrench, CheckSquare } from 'lucide-svelte';

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
	{ key: 'system', label: 'System', icon: Monitor },
	{ key: 'things', label: 'Things', icon: CheckSquare },
	{ key: 'storage', label: 'Storage', icon: HardDrive },
	{ key: 'shortcuts', label: 'Shortcuts', icon: Command },
	{ key: 'memory', label: 'Memory', icon: Brain },
	{ key: 'skills', label: 'Skills', icon: Wrench }
];
