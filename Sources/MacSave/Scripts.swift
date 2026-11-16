import Foundation

enum JXA {
    static let chromium = #"""
    function run(argv) {
      const app = Application(argv[0]);
      if (!app.running()) return "[]";
      const out = [];
      for (const w of app.windows()) {
        const o = {};
        try { o.name = w.name(); } catch (e) {}
        try { o.bounds = w.bounds(); } catch (e) {}
        try { o.minimized = w.minimized(); } catch (e) {}
        try { o.mode = w.mode(); } catch (e) {}
        try { o.titles = w.tabs.title(); o.urls = w.tabs.url(); } catch (e) { continue; }
        try { o.id = w.id(); o.tabIDs = w.tabs.id(); } catch (e) {}
        try { o.activeIndex = w.activeTabIndex(); } catch (e) {
          try { o.activeTitle = w.activeTab().title(); } catch (e2) {}
        }
        out.push(o);
      }
      return JSON.stringify(out);
    }
    """#

    static let safari = #"""
    function run(argv) {
      const app = Application(argv[0]);
      if (!app.running()) return "[]";
      const out = [];
      for (const w of app.windows()) {
        const o = {};
        try { o.name = w.name(); } catch (e) {}
        try { o.bounds = w.bounds(); } catch (e) {}
        try { o.minimized = w.miniaturized(); } catch (e) {}
        try { o.titles = w.tabs.name(); o.urls = w.tabs.url(); } catch (e) { continue; }
        try { o.id = w.id(); } catch (e) {}
        try { o.activeIndex = w.currentTab().index(); } catch (e) {}
        out.push(o);
      }
      return JSON.stringify(out);
    }
    """#

    static let iterm = #"""
    function run(argv) {
      const app = Application(argv[0]);
      if (!app.running()) return "[]";
      const out = [];
      for (const w of app.windows()) {
        const o = { tabs: [] };
        try { o.name = w.name(); } catch (e) {}
        try { o.bounds = w.bounds(); } catch (e) {}
        let cur = -1;
        try { cur = w.currentTab().index(); } catch (e) {}
        try {
          for (const t of w.tabs()) {
            const s = t.currentSession();
            const tab = {};
            try { tab.title = s.name(); } catch (e) {}
            try { tab.tty = s.tty(); } catch (e) {}
            try { tab.path = s.variable({ named: "session.path" }); } catch (e) {}
            try { tab.active = t.index() === cur; } catch (e) {}
            try { tab.panes = t.sessions().length; } catch (e) {}
            o.tabs.push(tab);
          }
        } catch (e) {}
        out.push(o);
      }
      return JSON.stringify(out);
    }
    """#

    static let terminal = #"""
    function run(argv) {
      const app = Application(argv[0]);
      if (!app.running()) return "[]";
      const out = [];
      for (const w of app.windows()) {
        const o = { tabs: [] };
        try { o.name = w.name(); } catch (e) {}
        try { o.bounds = w.bounds(); } catch (e) {}
        try { o.minimized = w.miniaturized(); } catch (e) {}
        try {
          for (const t of w.tabs()) {
            const tab = {};
            try { tab.title = t.customTitle(); } catch (e) {}
            try { tab.tty = t.tty(); } catch (e) {}
            try { tab.active = t.selected(); } catch (e) {}
            o.tabs.push(tab);
          }
        } catch (e) { continue; }
        out.push(o);
      }
      return JSON.stringify(out);
    }
    """#

    static let finder = #"""
    function run(argv) {
      const app = Application(argv[0]);
      const out = [];
      for (const w of app.finderWindows()) {
        const o = {};
        try { o.name = w.name(); } catch (e) {}
        try { o.bounds = w.bounds(); } catch (e) {}
        try { o.minimized = w.collapsed(); } catch (e) {}
        try { o.url = w.target().url(); } catch (e) {}
        out.push(o);
      }
      return JSON.stringify(out);
    }
    """#
}
