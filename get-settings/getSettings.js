const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
    const userIdentity = event.requestContext.authorizer.claims.sub;
    
    const tableName = 'user_settings'; 
    
    const params = {
        TableName: tableName,
        Key: {
            UserId: userIdentity
        }
    };
    
    try {
        const data = await dynamodb.get(params).promise();
        const theme = data.Item ? data.Item.Theme : 'dark';
        
        return {
            statusCode: 200,
            body: JSON.stringify({ theme })
        };
    } catch (error) {
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error })
        };
    }
};
