const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
    const userIdentity = event.requestContext.authorizer.claims.sub;
    
    const requestBody = JSON.parse(event.body || '{}');
    const theme = requestBody.theme || 'light';
    
    const tableName = 'user_settings'; 
    
    const updateParams = {
        TableName: tableName,
        Key: {
            UserId: userIdentity
        },
        UpdateExpression: 'SET Theme = :val',
        ExpressionAttributeValues: {
            ':val': theme
        }
    };
    
    try {
        await dynamodb.update(updateParams).promise();
        
        return {
            statusCode: 204 
        };
    } catch (error) {
        return {
            statusCode: 500,
            body: JSON.stringify({ error })
        };
    }
};
