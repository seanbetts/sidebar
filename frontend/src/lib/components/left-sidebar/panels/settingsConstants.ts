import { Brain, Monitor, User, Wrench } from 'lucide-svelte';

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
  { key: 'memory', label: 'Memory', icon: Brain },
  { key: 'skills', label: 'Skills', icon: Wrench }
];
