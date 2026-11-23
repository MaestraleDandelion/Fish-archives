(function () {
  const compact = matchMedia('(max-width: 768px), (pointer: coarse) and (max-width: 1000px) and (max-height: 550px)');

  window.$docsify.plugins = [].concat(window.$docsify.plugins || [], function (hook) {
    let focusWork = null;
    hook.mounted(() => {
      const sidebar = document.querySelector('aside.sidebar');
      const input = sidebar.querySelector('.search input');
      const anchor = document.createComment('原侧栏位置');
      sidebar.before(anchor);
      document.body.append(document.getElementById('mobile-controls').content.cloneNode(true));
      const bar = document.querySelector('.reader-bar');
      const dialog = document.getElementById('reader-dialog');
      const heading = document.getElementById('reader-heading');
      const close = dialog.querySelector('.reader-close');
      const searchButton = bar.querySelector('[data-panel="search"]');
      let lastHit = null;
      let refreshTimer;

      // 搜索插件将命中段落作为标题。多篇文章都可能有“要点”或“摘录”。
      function addSourceTitles() {
        if (!dialog.open || dialog.dataset.mode !== 'search') return;
        const titles = new Map(Array.from(sidebar.querySelectorAll('.sidebar-nav a'),
          link => [link.hash.split('?')[0], link.textContent.trim()]));
        for (const link of sidebar.querySelectorAll('.matching-post a')) {
          const page = link.hash.split('?')[0];
          const source = titles.get(page);
          if (!source || source === link.querySelector('h2')?.textContent || link.querySelector('.hit-source')) continue;
          const label = document.createElement('span');
          label.className = 'hit-source';
          label.textContent = source;
          link.prepend(label);
        }
      }
      const results = sidebar.querySelector('.results-panel');
      new MutationObserver(addSourceTitles).observe(results, {childList: true});

      function fitViewport() {
        const view = window.visualViewport;
        if (!dialog.open || !view) return;
        dialog.style.setProperty('--reader-top', view.offsetTop + 'px');
        dialog.style.setProperty('--reader-height', view.height + 'px');
      }

      function closePanel() {
        if (!dialog.open) return;
        clearTimeout(refreshTimer);
        if (dialog.contains(document.activeElement)) document.activeElement.blur();
        dialog.close();
        anchor.after(sidebar);
        focusWork = null;
      }

      // 初次打开时，资料可能还在下载。索引就绪后用当前词重新执行一次搜索。
      function refreshWhenIndexed(until) {
        if (!dialog.open || dialog.dataset.mode !== 'search') return;
        let indexed;
        try { indexed = Number(localStorage.getItem('docsify.search.expires')); }
        catch { return; }
        if (indexed >= performance.timeOrigin) {
          if (input.value.trim()) input.dispatchEvent(new Event('input', {bubbles: true}));
        } else if (Date.now() < until) {
          refreshTimer = setTimeout(() => refreshWhenIndexed(until), 450);
        }
      }

      function openPanel(mode, saved) {
        if (!compact.matches) return;
        dialog.dataset.mode = mode;
        heading.textContent = mode === 'search' ? '搜索档案' : '目录';
        dialog.append(sidebar);
        if (!dialog.open) dialog.showModal();
        fitViewport();
        if (mode === 'catalog') {
          close.focus();
          sidebar.querySelector('.active > a')?.scrollIntoView({block: 'nearest'});
          return;
        }
        if (saved) {
          if (input.value !== saved.query || !sidebar.querySelector('.results-panel.show')) {
            input.value = saved.query;
            input.dispatchEvent(new Event('input', {bubbles: true}));
          }
          close.focus();
          sidebar.scrollTop = saved.scroll;
        } else {
          input.focus();
          refreshWhenIndexed(Date.now() + 30000);
        }
        addSourceTitles();
      }

      function dismiss() {
        if (history.state?.archiveSearch) {
          const state = {...history.state};
          delete state.archiveSearch;
          history.replaceState(state, '');
        }
        closePanel();
      }
      bar.addEventListener('click', event => {
        const button = event.target.closest('[data-panel]');
        if (button) openPanel(button.dataset.panel, lastHit);
      });
      close.addEventListener('click', dismiss);
      dialog.addEventListener('cancel', event => {
        event.preventDefault();
        dismiss();
      });
      input.addEventListener('keydown', event => {
        if (dialog.open && event.key === 'Enter' && !event.isComposing) input.blur();
      });
      input.addEventListener('input', () => {
        if (lastHit && input.value !== lastHit.query) {
          lastHit = null;
          searchButton.textContent = '搜索档案';
        }
      });
      sidebar.addEventListener('click', event => {
        if (dialog.open && event.target.closest('.clear-button')) {
          lastHit = null;
          searchButton.textContent = '搜索档案';
          input.focus();
        }
        const link = event.target.closest('a');
        if (!dialog.open || !link) return;
        if (link.closest('.results-panel')) {
          lastHit = {query: input.value, scroll: sidebar.scrollTop};
          history.replaceState({...history.state, archiveSearch: lastHit}, '');
          searchButton.textContent = '返回搜索结果';
        } else if (link.closest('li')?.querySelector(':scope > ul')) {
          // 加载作品卡后，保留目录，让读者继续点选它的条目。
          focusWork = link.getAttribute('href');
          return;
        }
        closePanel();
      }, true);
      window.addEventListener('hashchange', () => {
        // 路由规范化可能触发多次 popstate；在 hash 确定后读取目的历史项。
        if (!compact.matches) return;
        if (history.state?.archiveSearch) {
          lastHit = history.state.archiveSearch;
          searchButton.textContent = '返回搜索结果';
          openPanel('search', lastHit);
        }
      });
      compact.addEventListener('change', closePanel);
      window.visualViewport?.addEventListener('resize', fitViewport);
      window.visualViewport?.addEventListener('scroll', fitViewport);
    });
    hook.doneEach(() => {
      if (focusWork) {
        const links = document.querySelectorAll('#reader-dialog .sidebar-nav a');
        Array.from(links).find(a => a.getAttribute('href') === focusWork)?.focus();
        focusWork = null;
      }
    });
  });
})();
