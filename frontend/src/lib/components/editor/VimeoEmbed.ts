import { Node, mergeAttributes } from '@tiptap/core';

export const VimeoEmbed = Node.create({
	name: 'vimeoEmbed',
	group: 'block',
	atom: true,

	addAttributes() {
		return {
			src: {
				default: null
			}
		};
	},

	parseHTML() {
		return [
			{
				tag: 'iframe[src*="player.vimeo.com"]',
				getAttrs: (node) => {
					if (!(node instanceof HTMLElement)) {
						return false;
					}
					return { src: node.getAttribute('src') };
				}
			}
		];
	},

	renderHTML({ HTMLAttributes }) {
		return [
			'iframe',
			mergeAttributes(HTMLAttributes, {
				class: 'video-embed',
				frameborder: '0',
				allow: 'fullscreen; picture-in-picture',
				allowfullscreen: 'true'
			})
		];
	}
});
