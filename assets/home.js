(function(){
  const entries = window.archiveEntries;
  if (!Array.isArray(entries)) return;
  const ordered = entries.slice().sort((a, b) => Date.parse(b.updated.at) - Date.parse(a.updated.at));
  const dateFormat=new Intl.DateTimeFormat('zh-CN',{timeZone:'Asia/Shanghai',year:'numeric',month:'long',day:'numeric'});
  let picked,bag=[];
  function draw(){
    if(!bag.length){
      bag=entries.slice();
      for(let i=bag.length-1;i>0;i--){
        const j=Math.floor(Math.random()*(i+1));
        [bag[i],bag[j]]=[bag[j],bag[i]];
      }
      if(bag.length>1 && bag.at(-1)===picked){
        [bag[0],bag[bag.length-1]]=[bag.at(-1),bag[0]];
      }
    }
    picked=bag.pop();
  }
  function route(e,vm){
    const [file,heading]=e.id.split(/#(.*)/s);
    const path='/'+file.replace(/\.md$/,'');
    if(!heading)return vm.router.toURL(path);
    const slug=window.Docsify.slugify;
    slug.clear();
    const id=slug(heading);
    slug.clear();
    return vm.router.toURL(path,{id});
  }
  function element(tag,text,parent){
    const el=document.createElement(tag);
    el.textContent=text;
    parent.append(el);
    return el;
  }
  function renderHome(article,vm){
    article.replaceChildren(document.getElementById('archive-home').content.cloneNode(true));
    const rows=article.querySelector('.rows');
    let previousDay,group;
    for(const e of ordered){
      const event=e.updated,day=dateFormat.format(new Date(event.at));
      if(day!==previousDay){
        const p=element('p','',rows);
        element('strong',day,p);
        group=element('ul','',rows);
        previousDay=day;
      }
      const li=element('li','',group);
      element('a',e.title,li).href=route(e,vm);
      const meta=element('span','',li);
      meta.className='details';
      element('span',event.kind,meta).className='type';
      meta.append('　原文 '+e.date);
    }
    const card=article.querySelector('.sea');
    const shuffle=card.querySelector('.another');
    shuffle.disabled=entries.length<2;
    function showCard(){
      card.querySelector('.category').textContent=picked?.kind||'暂无公开条目';
      card.querySelector('.pick strong').textContent=picked?.title||'';
      card.querySelector('blockquote p').textContent=picked?picked.excerpt:'';
      const link=card.querySelector('.readpick');
      link.hidden=!picked;
      if(picked)link.href=route(picked,vm);
    }
    if(!picked)draw();
    showCard();
    shuffle.addEventListener('click',()=>{draw();showCard();});
  }
  window.$docsify.plugins=[].concat(window.$docsify.plugins||[],function(hook,vm){
    const desktop = window.matchMedia('(min-width: 769px)');
    let original = null;
    function updateLayout() {
      const article = document.querySelector('.markdown-section');
      const home = ['/', '/README', '/README.md'].includes(vm.route.path);
      const useCards = home && desktop.matches;
      article.classList.toggle('archive-home-page', useCards);
      if (useCards && !article.querySelector('#whale-archive')) {
        original = Array.from(article.childNodes);
        renderHome(article, vm);
      } else if (!useCards && original && article.querySelector('#whale-archive')) {
        article.replaceChildren(...original);
        original = null;
      }
    }
    hook.doneEach(() => {
      original = null;
      updateLayout();
    });
    desktop.addEventListener('change', updateLayout);
  });
})();
