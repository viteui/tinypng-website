import * as path from 'path';
import { defineConfig } from 'rspress/config';
import ghPages from 'rspress-plugin-gh-pages';

// import toc from 'rspress-plugin-toc';

export default defineConfig({
  root: path.join(__dirname, 'docs'),
  title: 'TinyPNG',
  description: 'TinyPNG is a free online image optimizer',
  icon: '/rspress-icon.png',
  logo: {
    light: '/rspress-light-logo.png',
    dark: '/rspress-dark-logo.png',
  },
  plugins: [
    ghPages({
      siteBase: 'tinypng',
      repo: 'https://github.com/viteui/viteui.github.io.git',
      branch: 'tinypng',
    }),
  ],
  themeConfig: {
    socialLinks: [
      { icon: 'github', mode: 'link', content: 'https://github.com/viteui/tinypng-lib' },
    ],
  },
  // plugins: [
  //   toc({
  //     useOfficialComponent: true,
  //     tocHeading: '内容导航',
  //   })
  // ]
});
