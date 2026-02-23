export type SkillCredentialRequirement = {
	provider: string;
	key_kind: string;
	required: boolean;
};

export type SkillItem = {
	id: string;
	name: string;
	description: string;
	long_description?: string;
	how_it_works?: string;
	requirements?: string;
	category?: string;
	icon_key?: string;
	tier?: 'required' | 'standard' | 'store';
	user_toggleable?: boolean;
	installable?: boolean;
	status?: string;
	credential_requirements?: SkillCredentialRequirement[];
	version?: string;
	updated_at?: string;
	install_count?: number;
};
