#!/bin/bash

# ===================== 使用说明（发布前请保留） =====================
# 1. 将下方 YOUR_STACK_OCID 替换为你自己的 Stack OCID 后再运行。
# 2. Stack OCID 可在 OCI 控制台的 Resource Manager → Stacks → Stack 详情中查看。
# 3. 不要公开真实 Stack OCID、API 私钥、SSH 私钥、用户 OCID、租户 OCID 或 API Key 指纹。
# 4. 运行前请先确认：OCI CLI 已安装、API Key 已配置、且 `oci iam region list` 能正常返回结果。
# 5. 本脚本以实例数量增加作为成功判断；成功后会自动退出，请再到 OCI 控制台确认实例。
# =================================================================

STACK_OCID="YOUR_STACK_OCID"
REGION="ap-osaka-1"

# 1. 直接从配置文件获取租户根区间 OCID
COMPARTMENT_ID=$(grep -i "^tenancy=" ~/.oci/config | cut -d'=' -f2 | tr -d ' \r')

# 2. 获取初始实例数量（若为空则兜底设为 0）
INITIAL_COUNT=$(oci compute instance list --compartment-id "$COMPARTMENT_ID" --region "$REGION" --query "length(data)" --raw-output 2>/dev/null)
if ! [[ "$INITIAL_COUNT" =~ ^[0-9]+$ ]]; then
    INITIAL_COUNT=0
fi

echo "=== 开始 OCI 自动化抢机任务（终极极简稳健版）==="
echo "初始检测到已有实例数: $INITIAL_COUNT"

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] 发起 Stack Apply 作业..."
    
    # 提交堆栈 Apply 作业
    JOB_ID=$(oci resource-manager job create-apply-job \
      --stack-id "$STACK_OCID" \
      --execution-plan-strategy AUTO_APPROVED \
      --query "data.id" --raw-output 2>/dev/null)

    if [ -n "$JOB_ID" ] && [ "$JOB_ID" != "null" ]; then
        echo "[$TIMESTAMP] 作业已提交 (ID: $JOB_ID)，等待结果..."
        
        # 轮询等待 Job 运行结束（最多等待 3 分钟）
        JOB_STATE=""
        for i in {1..12}; do
            sleep 15
            JOB_STATE=$(oci resource-manager job get --job-id "$JOB_ID" --query "data.\"lifecycle-state\"" --raw-output 2>/dev/null)
            if [ "$JOB_STATE" == "SUCCEEDED" ] || [ "$JOB_STATE" == "FAILED" ]; then
                break
            fi
        done
        
        # 核心逻辑：核验实例数量变化
        CURRENT_COUNT=$(oci compute instance list --compartment-id "$COMPARTMENT_ID" --region "$REGION" --query "length(data)" --raw-output 2>/dev/null)
        if ! [[ "$CURRENT_COUNT" =~ ^[0-9]+$ ]]; then
            CURRENT_COUNT=$INITIAL_COUNT
        fi
        
        if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
            echo "🎉 [$TIMESTAMP] 确认成功！新实例已在控制台创建（实例数: $INITIAL_COUNT -> $CURRENT_COUNT）！"
            echo "抢机任务完成，脚本自动终止。"
            exit 0
        else
            echo "⚠️  [$TIMESTAMP] 堆栈执行结束（暂无机位或资源不足），准备下一次重试..."
        fi
    else
        echo "❌ [$TIMESTAMP] 提交作业失败（网络抖动或频控），稍后重试..."
    fi

    # 3. 3~6 分钟 (180s ~ 360s) 随机安全间隔，彻底防封
    RAND_WAIT=$((180 + RANDOM % 181))
    echo "[$TIMESTAMP] 安全退避等待 ${RAND_WAIT} 秒..."
    echo "----------------------------------------------------"
    sleep $RAND_WAIT
done
