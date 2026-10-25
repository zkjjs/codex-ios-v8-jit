/* 歪麦霸王餐 Loon port. Protocol reference: Sliverkiss/wmbwc.js (2025-07-07).
 * Upstream: https://gist.github.com/Sliverkiss/49a9ffb2169a2becc33bf4fdbf6eb99a
 * Credentials stay in Loon's wmbwc_data storage. No remote code loading.
 */
(function () {
  const dataKey = CryptoJS.enc.Utf8.parse('jnd674751fh6fkgu');
  const signKey = CryptoJS.enc.Utf8.parse('asdf545asdf4545d');
  const options = {mode: CryptoJS.mode.ECB, padding: CryptoJS.pad.Pkcs7};
  function encrypt(value, key = dataKey) { return CryptoJS.AES.encrypt(value, key, options).toString(); }
  function decrypt(value) { return CryptoJS.AES.decrypt(value, dataKey, options).toString(CryptoJS.enc.Utf8); }
  loonMain({
    name: '歪麦霸王餐', key: 'wmbwc_data', origin: 'https://wmapp-api.waimaimingtang.com',
    captureURL: '^https://wmapp-api\\.waimaimingtang\\.com/api/api/v2/user/api_user_info_one(?:\\?|$)',
    capture({request, headers, parse}) {
      const body = parse(request.body);
      const payload = parse(decrypt(body.json));
      return {userId: payload.userId, userName: String(payload.userId || ''), token: headers.token};
    },
    async run(account, http) {
      const base = {'user-agent':'Dart/3.7 (dart:io)', system:'iOS', 'x-user-agent':'user-agent', appversion:'1.1.154', 'content-type':'application/json;charset=UTF-8', token:account.token, application:'app', appchannel:'App Store', apiversion:'1'};
      async function call(endpoint, payload) {
        const timestamp = String(Date.now());
        const nonce = Array.from({length:16}, () => String(Math.floor(Math.random() * 9))).join('');
        const result = await http('/api/api/v2/user/' + endpoint, {...base, timestamp, 'x-fetch-ts':timestamp, nonce, sign:encrypt(timestamp + nonce, signKey)}, {json:encrypt(JSON.stringify(payload))});
        return result;
      }
      async function info() {
        const result = await call('api_user_info_one', {userId:account.userId, serviceNoStr:'api_user_info_one', city:'南宁市'});
        if (typeof result.data !== 'string') throw Error('用户信息获取失败，请重新获取账号');
        let data; try { data = JSON.parse(decrypt(result.data)); } catch (_) { throw Error('用户信息解密失败，接口可能已更新'); }
        const points = Number(data.integral);
        if (!Number.isFinite(points)) throw Error('用户信息缺少饭票数量，接口可能已更新');
        return points;
      }
      const before = await info();
      const sign = await call('api_user_sign_in', {userId:account.userId, userBehavior:'sign_in_v2', serviceNoStr:'api_user_sign_in'});
      let finished = 0;
      for (let i = 0; i < 6; i++) {
        const result = await call('api_user_video_task_token', {serviceNoStr:'api_user_video_task_token'});
        let token; try { token = decrypt(result.data); } catch (_) { throw Error('任务令牌获取失败'); }
        if (!token) throw Error('任务令牌为空，请在 App 中确认今日任务状态');
        const done = await call('api_user_task_finish', {serviceNoStr:'api_user_task_finish', taskKey:'view_video', userId:account.userId, token});
        if (!done || ![0,200,'0','200'].includes(done.code)) break;
        finished++;
      }
      const after = await info();
      return '饭票 ' + after + '（变化 ' + (after - before) + '），' + (sign.message || sign.msg || '签到已请求') + '，任务返回成功 ' + finished + ' 次';
    }
  });
})();
