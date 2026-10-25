/* Loon-only runtime. Uses local storage, documented HTTP callbacks and pass-through $done({}). */
async function loonMain(app) {
  const summaries = [];
  const isCapture = typeof $request !== 'undefined';
  function parse(value) { return typeof value === 'string' ? JSON.parse(value) : value; }
  function notify(subtitle, body) { $notification.post(app.name, subtitle, body || ''); }
  function headers(value) { const result = {}; for (const k of Object.keys(value || {})) result[k.toLowerCase()] = value[k]; return result; }
  function read() {
    const raw = $persistentStore.read(app.key);
    if (!raw) return [];
    const accounts = JSON.parse(raw);
    if (!Array.isArray(accounts)) throw Error('本地账号数据格式有误，请检查 ' + app.key);
    return accounts;
  }
  function save(account) {
    const accounts = read();
    const index = accounts.findIndex(a => String(a.userId) === account.userId);
    const previous = index >= 0 ? accounts[index] : null;
    if (index < 0) accounts.push(account); else accounts[index] = {...previous, ...account};
    if (!$persistentStore.write(JSON.stringify(accounts), app.key)) throw Error('账号保存失败，请检查 Loon 存储权限');
    if (!previous || previous.token !== account.token) notify('账号已保存', '已保存账号 ' + (index >= 0 ? index + 1 : accounts.length) + '，可手动运行签到验证。');
  }
  async function http(path, auth, body) {
    const options = {url: app.origin + path, headers: auth, timeout: 10000, 'auto-redirect': false};
    if (body !== undefined) options.body = JSON.stringify(body);
    return new Promise((resolve, reject) => {
      let settled = false;
      const timer = setTimeout(() => finish(Error('请求超时，请稍后重试')), 11000);
      function finish(error, result) { if (settled) return; settled = true; clearTimeout(timer); error ? reject(error) : resolve(result); }
      $httpClient[body === undefined ? 'get' : 'post'](options, (error, response, data) => {
        if (error) return finish(Error('网络请求失败，请检查连接'));
        const status = Number(response && (response.status || response.statusCode));
        if (status === 401 || status === 403) return finish(Error('登录已失效或无权限，请进入 App 的“我的”重新获取'));
        if (!(status >= 200 && status < 300)) return finish(Error('接口返回 HTTP ' + (status || '未知')));
        try {
          const value = parse(data);
          if (!value || typeof value !== 'object') throw Error();
          if (Number(value.code) === 401 || Number(value.code) === 403) return finish(Error('登录已失效，请重新获取账号'));
          finish(null, value);
        } catch (_) { finish(Error('接口返回格式异常，请检查 App 接口是否更新')); }
      });
    });
  }
  try {
    if (isCapture) {
      if (String($request.method).toUpperCase() === 'OPTIONS') return;
      if (!(new RegExp(app.captureURL)).test($request.url || '')) return;
      const account = app.capture({request:$request, response:typeof $response === 'undefined' ? null : $response, headers:headers($request.headers), parse});
      if (!account || !account.userId || !account.token) throw Error('获取账号失败：缺少用户标识或 token，请登录后重新进入“我的”');
      account.userId = String(account.userId);
      save(account);
    } else {
      const accounts = read();
      if (!accounts.length) { notify('尚未获取账号', '启用插件和 HTTPS 解密后，打开 ' + app.name + '，登录并进入“我的”。'); return; }
      let successful = 0;
      for (let index = 0; index < accounts.length; index++) {
        try {
          if (!accounts[index] || !accounts[index].token) throw Error('账号缺少 token，请重新获取');
          const result = await app.run(accounts[index], http);
          summaries.push('账号' + (index + 1) + '：' + result);
          successful++;
        } catch (error) {
          // Never log transport error strings or authentication headers.
          summaries.push('账号' + (index + 1) + '：' + String(error.message || '执行失败').split(String(accounts[index] && accounts[index].token || '\u0000')).join('[已隐藏]'));
        }
      }
      notify('共' + accounts.length + '个账号，成功' + successful + '个，失败' + (accounts.length - successful) + '个', summaries.join('\n'));
    }
  } catch (error) {
    notify(isCapture ? '账号获取未完成' : '运行未完成', isCapture ? '请确认已登录并进入“我的”；若持续失败，请检查接口或清理格式错误的本地账号数据。' : '本地账号数据读取失败，请检查 ' + app.key);
  } finally {
    $done({});
  }
}

/* 晓晓优选 Loon port. Protocol reference: Sliverkiss/xxyx.js (2025-07-09).
 * Upstream: https://gist.github.com/Sliverkiss/991a81be1fc8cf2a1937432be68f5521
 * Keeps xxyx_data compatibility; omits upstream's forced referral binding.
 */
(function () {
  loonMain({
    name:'晓晓优选', key:'xxyx_data', origin:'https://xxyx-client-api.xiaoxiaoyouxuan.com',
    captureURL:'^https://xxyx-client-api\\.xiaoxiaoyouxuan\\.com/my(?:\\?|$)',
    capture({headers, response, parse}) {
      const data = parse(response && response.body).data || {};
      return {userId:data.identityId, userName:data.nick || data.mobile || String(data.identityId || ''), token:headers['xx-token']};
    },
    async run(account, http) {
      const headers = {'xx-platform':'ios', 'User-Agent':'XiaoXiaoYouXuan/20127 CFNetwork/1331.0.7 Darwin/21.4.0', 'xx-version':'30221', 'xx-token':account.token, 'Content-Type':'application/json;charset=utf-8'};
      async function energy() {
        const r = await http('/client/energy/mall/getUserEnergy?platform=ios', headers);
        if (!r.data || !Number.isFinite(Number(r.data.energy))) throw Error('能量查询失败，请重新获取账号');
        return Number(r.data.energy);
      }
      const before = await energy();
      const sign = await http('/client/energy/mall/signIn', headers, {platform:'ios'});
      const result = await http('/client/energy/mall/getTaskList', headers);
      if (!Array.isArray(result.data)) throw Error('任务列表格式异常，接口可能已更新');
      let completed = 0;
      for (const task of result.data) {
        if (Number(task.isCompleted) !== 0 || task.taskId === undefined || task.taskId === null) continue;
        const times = Math.max(0, Math.min(20, Math.floor(Number(task.remainingCount ?? task.dailyCount) || 0)));
        for (let i = 0; i < times; i++) {
          const r = await http('/client/energy/mall/completeTask/' + encodeURIComponent(String(task.taskId)), headers, {taskId:task.taskId, platform:'ios'});
          if (![0,200,'0','200'].includes(r.code)) break;
          completed++;
        }
      }
      const after = await energy();
      return '能量 ' + after + '（变化 ' + (after - before) + '），' + (sign.msg || sign.message || '签到已请求') + '，任务返回成功 ' + completed + ' 次';
    }
  });
})();
