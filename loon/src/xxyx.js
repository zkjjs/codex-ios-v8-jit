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
