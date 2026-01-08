import { Image } from '@tiptap/extension-image';

export const ImageWithCaption = Image.extend({
	renderHTML({ HTMLAttributes }) {
		const caption = HTMLAttributes.title;
		if (caption) {
			return [
				'figure',
				{ class: 'image-block' },
				['img', HTMLAttributes],
				['figcaption', { class: 'image-caption' }, caption]
			];
		}
		return ['img', HTMLAttributes];
	}
});
