import { Node } from '@tiptap/core';

export const ImageGallery = Node.create({
  name: 'imageGallery',
  group: 'block',
  content: 'block+',
  isolating: true,

  addAttributes() {
    return {
      caption: {
        default: null
      }
    };
  },

  parseHTML() {
    return [
      {
        tag: 'figure.image-gallery',
        contentElement: 'div.image-gallery-grid',
        getAttrs: node => {
          if (!(node instanceof HTMLElement)) {
            return false;
          }
          return {
            caption: node.getAttribute('data-caption')
          };
        }
      }
    ];
  },

  renderHTML({ node }) {
    const caption = node.attrs.caption;
    const figureAttrs: Record<string, string> = { class: 'image-gallery' };
    if (caption) {
      figureAttrs['data-caption'] = caption;
    }
    const children: any[] = [
      ['div', { class: 'image-gallery-grid' }, 0]
    ];
    if (caption) {
      children.push(['figcaption', { class: 'image-caption' }, caption]);
    }
    return ['figure', figureAttrs, ...children];
  }
});
